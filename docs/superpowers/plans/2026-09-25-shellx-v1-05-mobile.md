# ShellX v1.0 — Plan 05: Mobile app (`apps/mobile`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. This plan is part of the ShellX v1.0 plan set: read `docs/superpowers/plans/2026-09-25-shellx-v1-00-overview.md` first — its Global Constraints and interface contracts (§4–§5) are binding here.

**Goal:** Build the ShellX Flutter app for iOS 15+ and Android 8.0 (API 26)+ on the team's Flutter base (`flutter-base/yallabb`): sign in/up, list the account's computers with live presence, pair by QR, open terminal tabs on a computer (xterm.dart + extra keys bar, copy/paste, pinch zoom and an "Aa" font slider, hardware keyboard, reconnect on resume), biometric lock, settings (font size, lock, unpair, sign out, delete account, version) — laid out exactly as the approved UI design.

**Architecture:** The app is a copy of the team base `yallabb` (feature-first `data/domain/presentation`, `get_it` + `injectable`, `auto_route` with guards, `signals_flutter` `Controller`/`StateSignal`/`Watch`, `intl_utils` `S.of(context)`, the base design system with `context.colors`/`context.typo`, `AppButton`/`AppTextField`, `PopupHandler` toasts) with the demo features and the `dio`/refresh-token stack removed. ShellX logic is a thin layer over `shellx_core` (REST, relay connection, identity, pairing URI) and `shellx_client` (machine channels, tabs, pairing initiator), consumed **only** through the signatures in overview §5.1–§5.7. Because those classes are `final`, the app talks to them through three small app-side ports (`ShellxBackend`, `MachineSession`, `TabHandle`) with one production adapter (`ClientBackend`) and test fakes. State lives in `Controller` subclasses holding signals (lock, extra keys, terminal tabs/workspace/page, scanner, settings, machine list, login/register) that are unit-tested without widgets; one `SessionHolder` owns the account, the backend and the relay lifecycle and announces sign-in/sign-out on the base's `AuthEventNotifier`, which the `SessionEnforcer` turns into navigation. Pages get their controllers from `getIt`.

**Tech Stack:** Flutter 3.41.7 / Dart 3.11.5 (pub workspace member), team base packages (`signals_flutter` 6.3.1, `get_it` 9.3.0, `injectable` 2.7.1+4, `auto_route` 11.1.0, `intl` 0.20.2 + `intl_utils` 2.8.14, `flutter_gen_runner` 5.15.0, `adaptive_theme` 3.7.2, `toastification` 3.2.0, `equatable` 2.1.0, `shared_preferences` 2.5.5, `flutter_secure_storage` 10.3.4), ShellX packages (`xterm` 4.0.0, `mobile_scanner` 7.4.2, `local_auth` 3.0.2, `package_info_plus` 9.0.1, `device_info_plus` 12.4.0, `url_launcher` 6.3.2, `app_settings` 7.0.0); code generators `build_runner` 2.15.1, `injectable_generator` 2.12.1, `auto_route_generator` 10.5.0 (with `dart_style` 3.1.7); tests: `flutter_test`, `fake_async` 1.3.3, `http` 1.6.0 (`MockClient`). Fonts: Raleway (UI, from the base, SIL OFL 1.1) and JetBrains Mono 2.304 (terminal, SIL OFL 1.1).

**Spec:** `docs/superpowers/specs/2026-09-25-shellx-v1-design.md` (§5.2, §5.3, §5.5, §5.6, §9, §12, §13 mobile parts). **Overview:** `docs/superpowers/plans/2026-09-25-shellx-v1-00-overview.md`. **Handoff decisions:** `docs/superpowers/HANDOFF.md` §6 (mobile on the yallabb base).

**UI design — binding for every UI task (Tasks 2, 4, 7, 14, 15, 16, 18, 19):** `docs/superpowers/design/2026-09-25-shellx-mobile-ui.html` (approved by the user on 2026-09-25; spec §9.2 references it). Layout, Vietnamese copy (verbatim; English equivalents in `intl_en.arb`), states and colours of every screen come from it: the light `--a-*` palette is the base's `LightColors`, the dark `--a-*` palette replaces the base's placeholder `DarkColors`, the `--t-*` terminal palette is the xterm theme (dark in both app themes), UI text is Raleway with lining numerals, the terminal is JetBrains Mono, and every touch target is at least 44 pt. When this plan's prose and the design disagree on something visual, the design wins; behaviour (spec, overview contracts, Review Focus) wins over the design.

**Team base:** `/Users/lehuuphu/Documents/workspace/DigitalUnicorn/flutter-base/yallabb`, `HEAD` `2437b6f` plus its uncommitted `pubspec.yaml` change (`signals_flutter: ^6.3.0` from pub instead of a git fork). Read-only: Task 1 copies its working tree, nothing ever writes to it.

**Depends on (gates):** every task compiles against the real public API of the packages below; nothing here re-implements protocol, crypto or session logic.

| Tasks | Needs merged into the branch this plan runs on |
|---|---|
| 1–8 | plan 02 (`packages/shellx_core`, root `pubspec.yaml` workspace). They do not touch `ClientService`: scaffold, design system, platform adapters and stores, biometric lock, terminal input primitives, extra keys, xterm wrapper, grid measurement. Start them right away. |
| 9 | plan 03 up to Task 10 (`packages/shellx_client` exists with the §5.7 types: `MachineConnectionFailure`, `MachineFailed`, `MachineConnectionException`, `AppErrorException`, `TabEvent`, `SessionInfo`). |
| 10–19 | plan 03 Tasks 11–14 (`ClientService`, `MachineClient`, `ClientTab`, `PinnedStore`, pairing initiator) — the backend adapter, the session holder and every screen that talks to a computer. |

**Working directory:** unless a step says otherwise, run commands from `apps/mobile` (for example `cd apps/mobile && flutter test test/features/terminal`). Git commands run from the repository root.

---

## Global Constraints

Everything in overview §2 applies (Dart `^3.11.0` / Flutter 3.41, bilingual UI, never log payloads/tokens/passwords, never send application data unencrypted, Conventional Commits with at least one commit per task, …). Plan-specific values, copied from the spec (and the coordinator's amendments) verbatim:

- Platforms: "Mobile app cho iOS 15+ và Android 8.0 (API 26)+." → iOS deployment target **15.0**, Android **minSdk 26**.
- Identity: bundle id / applicationId / Android namespace **`pro.shellx.mobile`** (Kotlin package directory `pro/shellx/mobile`), display name **"ShellX"**, Dart package **`shellx_mobile`**. The base name `yallabb` must not survive anywhere in `lib`, `test`, `android` or `ios` (Task 1 pins this with a test).
- Crypto (coordinator ruling, overrides the `cryptography_flutter` entry of spec §9.1): the app does **not** depend on `cryptography_flutter` and never calls `FlutterCryptography.enable()`. `shellx_core` pins the pure-Dart `DartX25519`, `DartChacha20.poly1305Aead`, `DartBlake2s` backends so the vector-tested Noise code runs identically everywhere and failures stay `NoiseException`. Task 1 pins this with a test.
- §5.1: "Khóa bí mật không bao giờ rời thiết bị … Cài lại app sinh khóa mới, nên phải ghép nối lại." → Keychain items use `first_unlock_this_device`; Android backup disabled; a fresh install wipes secure storage.
- §5.2: "Đăng xuất trên mobile: chỉ xóa token. Khóa thiết bị và danh sách máy đã ghim được giữ lại (lưu theo `user_id`) … Tài khoản khác đăng nhập trên cùng điện thoại không thấy dữ liệu đó."
- §5.2 (amended): "Xóa tài khoản … trong Cài đặt của mobile app, người dùng nhập lại mật khẩu để xác nhận." `ShellxApi.deleteAccount(password)` → `DELETE /v1/account`; `401 invalid_credentials` → "Mật khẩu không đúng." under the password field; on success delete the token, the device private key and this user's pinned machines, stop `ClientService`, go to the login screen.
- Passwords: 8–128 characters on sign-up and nothing else (spec §5.2); the sign-in and delete-account password is only required. Email format is checked with the base's `validateEmailWithMessages`; disposable addresses are rejected by the relay (`disposable_email`) and shown inline under the email field.
- §5.6: "Face ID / vân tay / mã máy qua `local_auth`. Mặc định bật. Yêu cầu mở khóa khi mở app và khi quay lại sau hơn 5 phút ở nền."
- §9.3: "Một hàng cuộn ngang: `Esc` `Tab` `Ctrl` `Alt` `↑` `↓` `←` `→` `|` `~` `/` `-` `Home` `End` `PgUp` `PgDn` `Dán`." and "`Ctrl` và `Alt` là phím dính: chạm một lần áp dụng cho phím kế tiếp; chạm hai lần khóa lại cho tới khi chạm lần nữa." Design: a one-shot modifier is a plain key with a primary outline, a locked one is filled primary with a dot.
- §9.4: long-press select + copy; bracketed paste when the application enabled it; pinch (and the design's "Aa" slider) change the font size; rotate/resize → `resize`; hardware keyboards work; channels to every machine with open tabs while in the foreground; on return from background: reconnect, re-handshake, re-attach with `last_seq` (the last two are done by `shellx_client`; the app suspends the backend — `ClientService.stop()` — when paused and resumes it — `ClientService.start()` — when back, or calls `RelayConnection.reconnectNow()` for a relay that is merely `disconnected`).
- §9.5: secure storage holds the device private key, token, `device_id`, pinned machines per `user_id`.
- §12 texts (Vietnamese, verbatim; English equivalents live in `intl_en.arb`): "Mất kết nối, đang thử lại…"; "Lần cuối online: …"; "Máy không còn tin cậy điện thoại này. Hãy ghép nối lại."; "Mã QR không hợp lệ hoặc đã hết hạn. Hãy tạo mã mới trên máy tính."; "Máy này không thuộc tài khoản của bạn. Hãy đăng nhập cùng tài khoản trên máy tính."; "Cần cập nhật app"; "Máy đã mở tối đa 10 phiên. Hãy đóng bớt phiên."; `spawn_failed` shows the reason in the tab; 4002 → delete token, back to login (design: banner "Phiên đăng nhập đã hết hiệu lực. Hãy đăng nhập lại." with the email prefilled); 4001 → no automatic reconnect; HTTP 429 → "Thử lại sau ít phút."; Review Focus 3 → "Phiên đã kết thúc".
- User-facing errors: every failure a user sees goes through `ErrorText` (Task 9) — the §12 texts above or a localized fallback — never an exception's `toString()`. `Controller.guard` shows it in a `PopupHandler` toast; the design's inline states (register fields, delete-account password, pairing sheet, terminal notices) show it in place.
- Logging: only `debugPrint` inside `if (kDebugMode)`, and only an error's `runtimeType` — never an API/relay error object, a payload, a token or a password. The base's `print`/`log` calls are rewritten accordingly in Task 1.
- REST only through `ShellxApi` of `shellx_core` (`package:http`); the base's `dio`/`RestClient`/`AuthInterceptor`/refresh-token stack is deleted. One opaque device token, no refresh token.
- Dependency injection: exactly one `KeyValueStore` (`@lazySingleton` `Module.keyValueStore`, a `SecureKeyValueStore`) for the whole app — `DeviceIdentity.loadOrCreate` only de-duplicates concurrent calls on the same instance (overview §5.5). Task 3 pins this with a test on the generated config.
- Storage keys: contract-owned `device_private_key` (`DeviceIdentity.storageKey`) and `pinned_machines_<userId>` (`PinnedStore`); plan-owned `auth_token`, `auth_user_id`, `auth_device_id`, `auth_email`, `settings_font_size`, `settings_biometric_lock` (secure storage) and `shellx_installed` (SharedPreferences).
- Contract facts from plans 02/03 (as written): a WebSocket upgrade rejected with 401 also ends in `RelayConnectionState.revoked`; REST 401 for a bad token has code `unauthorized`; the rate limit is recognised by **status 429**; network errors are status 0, code `network`; `ShellxApi.login/register` set `api.token`, `logout()` clears it; `RelayConnection.start()` may be called again after `stop()`/`replaced`/`revoked`, `reconnectNow()` acts only while `disconnected`; `ClientService.start()` loads the pins, subscribes and calls `relay.start()`, `ClientService.stop()` calls `relay.stop()` and may be followed by `start()` again; `MachineClient.connect()` and requests throw `MachineConnectionException(failure)` (plan 03 addition) after moving to `MachineFailed`; `MachineClient` forgets the pin on `untrusted`; re-attaching an existing tab reuses the same `ClientTab` with `last_seq = received`; `ClientTab.events` replays events emitted before its first listener; `closeTab` only sends `session.close` for an attached tab.
- Code style of the base: single quotes, `package:shellx_mobile/core/core.dart` / `shared/shared.dart` barrel imports (test files import `core.dart` with `hide test` — `injectable` exports a `test` constant), `context.colors`/`context.typo`, `AppButton`/`AppTextField`, `N.sizedHeight`/`N.sizedWidth`, `formatter: page_width: 120`.
- Generated code (`lib/shared/src/l10n.dart`, `lib/shared/src/intl/`, `lib/shared/src/{assets,fonts}.gen.dart`, `lib/core/dependency/dependency.config.dart`, `lib/core/router/app_router.gr.dart`) is committed. After changing an ARB file run `dart run intl_utils:generate`; after adding or changing an annotated class, route or asset run `dart run build_runner build`. CI fails when either leaves a diff.
- Test command (overview §3): `flutter test` in `apps/mobile`. Never add `test` above 1.30 to this app — Flutter 3.41.7 pins `test_api 0.7.10`, and the whole workspace resolves together.

### Rulings made while writing this plan

Format: `Ruling: <decision> — <why> — <cost if wrong>`.

- Ruling: copy the base with `rsync` (excluding `.git`, `.vscode`, `.fvmrc`, `.idea`, `pubspec.lock`, build/tool output and generated plugin registrants), then delete, rename and rewrite as Task 1 lists — the user asked for yallabb as the base and the copy keeps its files byte-for-byte — copy again.
- Ruling: `auto_route: 11.1.0` exactly — 11.2.0 (what `^11.1.0` resolves to today) calls `Viewport.scrollCacheExtent`, which Flutter 3.41.7 does not have, so nothing compiles — lift the pin when the workspace moves to a newer Flutter.
- Ruling: `device_info_plus: ^12.3.0` (resolves 12.4.0) — 13.x needs `win32` ^6 while `apps/desktop`'s `package_info_plus` 9 needs `win32` ^5, and the workspace resolves together — bump both apps together later.
- Ruling: `flutter_secure_storage: ^10.3.4` and `package_info_plus: ^9.0.1` — the versions `apps/desktop` pins, so both apps resolve together — none.
- Ruling: `app_settings: 7.0.0` exactly — 8.x/9.x ship only a Swift Package Manager iOS target and the app builds with CocoaPods (the base's `Podfile`) — switch when the app moves to SwiftPM.
- Ruling: the code generators are pinned exactly (`build_runner` 2.15.1, `injectable_generator` 2.12.1, `auto_route_generator` 10.5.0, `flutter_gen_runner` 5.15.0, `intl_utils` 2.8.14, `dart_style` 3.1.7) — `pubspec.lock` is git-ignored in this repository, and a different generator or formatter version would make the CI freshness check fail on untouched code — bump them together with a regenerate commit.
- Ruling: `dart run build_runner build` without `--delete-conflicting-outputs` — build_runner 2.15 removed the flag (it only prints a warning) and always overwrites its own outputs — none.
- Ruling: `@InjectableInit(throwOnMissingDependencies: true)` — a missing registration then fails `build_runner` instead of crashing at launch — none.
- Ruling: drop `dio`, `awesome_dio_interceptor`, `json_annotation`/`json_serializable` (+ `build.yaml`), `uuid`, `change_app_package_name`, `flutter_launcher_icons` and the base's `lottie` integration; `http` becomes a dev dependency (tests only, `MockClient`) — ShellX has no DTOs of its own (REST models come from `shellx_core`), no refresh token, and no launcher-icon tooling yet — add a package back when it is used.
- Ruling: delete the base's demo features (`single`, `list`, `entry_testing`), its auth feature except `PasswordTextField`, `lib/core/{auth,client,models}`, `RefreshTokenHandler`, the base `AuthGuard`, the French ARB, `README.md`, `docs/auth_flows.md`, `test/widget_test.dart`, `test/features`, the manual phone-validator test and the `com/example` Kotlin package; keep the rest of the base (architecture, design system, handlers, shared widgets and paging views, validators and their tests, `docs/state_signal_guide.md`) — keeping unused base widgets costs nothing and keeps the base recognisable — delete later.
- Ruling: the biometric lock is an overlay installed by `MaterialApp.router`'s `builder` (`LockGate`), not a route guard — guards only run on navigation, while the lock must cover every route and dialog when the app comes back from the background — none.
- Ruling: controllers never navigate; `SessionHolder` announces `SignedInEvent`/`SignedOutEvent` on the base's `AuthEventNotifier`, and `SessionEnforcer` does `replaceAll` to the machine list or the login page (the base's pattern) — keeps controllers unit-testable without a router — none.
- Ruling: the relay rejects disposable emails (`disposable_email`) and the app shows that inline; the app ships no disposable-domain list — one source of truth — none.
- Ruling: store links are `AppConfig.appStorePage` (`--dart-define=SHELLX_APP_STORE_URL`, default `https://shellx.pro/` until the App Store id exists) and `AppConfig.playStorePage` (`https://play.google.com/store/apps/details?id=pro.shellx.mobile`) — the App Store id is not known before the first submission — set the define in the release build.
- Ruling: the licences page opens from a tap on the version footer in Settings (the design has no separate row); both OFL licences are registered with `LicenseRegistry` — none.
- Ruling: the base's one-second splash delay is removed; the splash page runs `configureDependencies()` and `prepareLaunch()` — the lock and the version gate need no artificial wait — none.
- Ruling: the design's "1×" zoom chip is not built — spec §9.4 has pinch zoom and the design's "Aa" slider already shows the size — add it if users ask.
- Ruling: `ios/Podfile.lock` is committed after the first `flutter build ios` (Task 19), like `apps/desktop/macos/Podfile.lock`; Task 1 already contains the UIScene migration that Flutter 3.41's `flutter build ios` applies (`FlutterSceneDelegate`, `FlutterImplicitEngineDelegate`, no `MinimumOSVersion` in `AppFrameworkInfo.plist`) so a build leaves no diff — none.

## Review Focus

Overview lines owned (partly) by this plan, then plan-specific inputs most likely to bite a user. Each line names the test that pins it.

1. **Overview RF 3 (UI):** a tab whose attach fails with `session_not_found` — when picked from the session sheet or when `shellx_client` re-attaches after a reconnect — shows "Phiên đã kết thúc" and can still be closed. Tests: Task 12 `Review Focus 3: session_not_found while reattaching ends the tab`, Task 13 `Review Focus 3: attach → session_not_found gives a closable "ended" tab`, Task 14 widget test `Review Focus 3: a session that vanished shows "Phiên đã kết thúc" and can be closed`.
2. **Overview RF 4 (client side):** a zero-height or zero-width terminal (keyboard sliding, rotation) must never produce a `resize` below 1×1, and opening a session with an unmeasurable viewport uses a sane fallback. Tests: Task 12 `Review Focus 4: a zero-sized viewport is never sent`, Task 8 `Review Focus 4: null when not even one cell fits`, Task 14 `first open without sessions opens a tab automatically; the chrome shows the machine` (asserts cols/rows ≥ 1).
3. **Soft keyboard + sticky Ctrl/Alt inside full-screen programs:** tapping `Ctrl` then typing `c` on the iOS/Android keyboard must send `^C`; `Alt` must keep the typed letter's case; arrows must switch to `ESC O A` when vim/htop/less enable DECCKM. xterm.dart 4.0.0 gets DECCKM and Alt/Shift+arrow wrong, so this is fixed and pinned. Tests: Task 5 `arrows follow DECCKM (application cursor mode)`, `modifier parameter is 1 + shift + 2*alt + 4*ctrl`; Task 7 `soft keyboard: sticky Ctrl turns "c" into ^C`, `soft keyboard: sticky Alt keeps the typed case`, `tap Ctrl then type c on the soft keyboard sends ^C`.
4. **Hardware keyboard on Android:** `Ctrl+A` (tmux prefix, readline) and `Ctrl+V` (vim block mode) must reach the shell; xterm.dart's default shortcuts would turn them into select-all/paste. Test: Task 5 `Android never captures Ctrl+A or Ctrl+V`.
5. **Multi-line paste:** clipboard text with `\n` or `\r\n` is sent with CR line breaks, wrapped in bracketed-paste markers when the program enabled mode 2004, and never picks up a pending sticky modifier. Test: Task 7 `paste: bracketed when enabled, CR line breaks, never modified`.
6. **Deleting the account:** the relay closes every socket with 4002 as part of the deletion; that must not be shown as "revoked", and another account's pinned machines on the same phone must survive. Tests: Task 11 `the 4002 close that accompanies the deletion is not treated as a revocation`, `success forgets token, device key and this user's pins only`.
7. **Reinstall on iOS:** Keychain survives app deletion; the first launch after a reinstall must start from a clean secure store (new device key, spec §5.1). Test: Task 3 `wipes once on the first launch, then never again`.
8. **One device key per phone:** two `KeyValueStore` instances would let two concurrent `DeviceIdentity.loadOrCreate` calls generate two keys. Test: Task 3 `one shared KeyValueStore for the whole app (overview §5.5)`.
9. **No secrets in logs or toasts:** the base printed guard errors and used `error.toString()` as the toast title — an `ApiException` can carry request details. Tests: Task 9 `guard shows the spec §12 text and never logs the error itself`; Task 3 `the session never prints its token`.
10. **4001 is never retried automatically, 4002 returns to login:** Tests: Task 11 `a replaced (4001) connection is never resumed automatically`, `close code 4002 (revoked) deletes the token and signs out (spec §12)`; Task 19 `after a 4002: the expired banner and the email prefilled`, `a revoked token while a terminal is open goes back to login (spec §12)`.
11. **Design states that change behaviour:** an offline machine card is dimmed and not tappable; a one-shot vs locked Ctrl looks different; an ended session keeps its output with "Đóng tab"/"Mở phiên mới". Tests: Task 18 `online paired opens the terminal; unpaired opens the scanner; offline is not tappable`; Task 7 `design: Ctrl once = primary outline on a plain key, locked = filled with a dot`; Task 14 `design: an exited session keeps its content; "Mở phiên mới" replaces the tab`.

## Verified package APIs (checked against the sources in `~/.pub-cache`, Flutter 3.41.7)

| Package | Version | What this plan relies on |
|---|---|---|
| `signals_flutter` / `signals_core` | 6.3.1 | `signal<T>(v)` (a `FlutterSignal`), `computed`, `effect` (runs immediately), `batch`; `ReadonlySignal.value/peek()/subscribe` (subscribe runs immediately with the current value); `Signal.dispose()` — writing a disposed signal throws `SignalsWriteAfterDisposeError`; default equality is `identical`; `Watch((context) => …)` rebuilds only for signals read inside its own builder (not in child `build` methods). |
| `injectable` / `injectable_generator` | 2.7.1+4 / 2.12.1 | `@injectable`, `@lazySingleton`, `@singleton`, `@LazySingleton(as:)`, `@Singleton(as:)`, `@module`, `@preResolve`, `@PostConstruct(preResolve: true)`, `@factoryMethod` on a static method, `@factoryParam` (`getIt<T>(param1: …)`), `@disposeMethod`, `@InjectableInit(throwOnMissingDependencies: true)`. `package:injectable` exports a top-level `test` constant (hence `hide test` in test files). |
| `get_it` | 9.3.0 | `GetIt.instance`, `getIt<T>()`, `getIt<T>(param1: …)`, `reset()`, `registerSingleton`/`registerFactory`/`registerFactoryParam` (tests). |
| `auto_route` / `auto_route_generator` | 11.1.0 / 10.5.0 | `@RoutePage()` (generates `XRoute` for `XPage`), `@AutoRouterConfig(replaceInRouteName:)`, `RootStackRouter.routes`, `AutoRoute(page:, initial:, guards:)`, `AutoRouteGuard.onNavigation(NavigationResolver resolver, StackRouter router)` with `resolver.next(bool)`, `router.replace/replaceAll/push<T>/maybePop`, `context.router`, `PageInfo(name, builder: (RouteData data) …)`, `RootStackRouter.config(navigatorObservers:)`, `navigatorKey`. |
| `intl_utils` | 2.8.14 | `flutter_intl: enabled: true, output_dir: lib/shared/src/` → `S` in `lib/shared/src/l10n.dart` + `lib/shared/src/intl/messages_*.dart` from `lib/l10n/intl_{en,vi}.arb`; `S.of(context)`, `S.current`, `S.load(Locale)` (sets the process-wide Intl locale — tests load one locale at a time), `S.delegate.supportedLocales`; ICU plurals and placeholders become methods. |
| `flutter_gen_runner` | 5.15.0 | `flutter_gen: output: lib/shared/src/` → `Assets.icons.*`, `Assets.licenses.jetBrainsMonoOFL`/`ralewayOFL` (paths), `FontFamily.jetBrainsMono` (`'JetBrainsMono'`), `FontFamily.raleway`. |
| `adaptive_theme` / `toastification` | 3.7.2 / 3.2.0 | `AdaptiveTheme.of(context).mode`, `AdaptiveTheme.getThemeMode()` (reads `SharedPreferencesAsync` — tests set `SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty()` from `shared_preferences_platform_interface` 2.4.2); `ToastificationWrapper`, `toastification.show`. |
| `xterm` | 4.0.0 | `Terminal({maxLines, inputHandler, onOutput, onResize, onTitleChange})`, `write`, `keyInput(TerminalKey, {shift, alt, ctrl})`, `textInput`, `paste` (wraps `ESC[200~…ESC[201~` when `bracketedPasteMode`), `resize` (clamps to ≥1), `cursorKeysMode`, `buffer.getText(range)`; `CascadeInputHandler`, `defaultInputHandler`, `TerminalKeyboardEvent`; `TerminalView(terminal, {controller, focusNode, theme, textStyle, padding, autofocus, deleteDetection, readOnly, shortcuts})`; `TerminalTheme(...)` (all 16 ANSI colours + cursor/selection/search), `TerminalController.selection/clearSelection`; `TerminalStyle({fontSize, fontFamily})`. `TerminalView` feeds soft-keyboard text as `keyInput(key)` then falls back to `textInput(text)`. RIS (`ESC c`) is **not** supported → a reset swaps in a new `Terminal`. Keytab quirks: app-cursor mode follows DECKPAM instead of DECCKM; Alt/Shift+arrow encoded as Ctrl+arrow; `charInput` has no uppercase Ctrl and sends Alt+letter uppercase. |
| `mobile_scanner` | 7.4.2 | `MobileScanner({controller, onDetect, errorBuilder: (BuildContext, MobileScannerException)})`, `MobileScannerController({formats, detectionSpeed})`, `BarcodeCapture.barcodes`, `Barcode.rawValue`, `MobileScannerErrorCode.permissionDenied`. Declares `CAMERA` itself; iOS needs `NSCameraUsageDescription`. |
| `local_auth` | 3.0.2 (android 2.0.8, darwin 2.0.4) | `LocalAuthentication().authenticate({localizedReason, biometricOnly, persistAcrossBackgrounding})`, `isDeviceSupported()`, `getAvailableBiometrics()` → `BiometricType.face/fingerprint/strong/weak`, `LocalAuthException.code` (`LocalAuthExceptionCode.noCredentialsSet`). Android: `FlutterFragmentActivity`, `USE_BIOMETRIC`, AppCompat launch theme on Android 8. iOS: `NSFaceIDUsageDescription`. |
| `flutter_secure_storage` | 10.3.4 | `const FlutterSecureStorage({iOptions})`, `read/write/delete/deleteAll`, `IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device)`, `FlutterSecureStorage.setMockInitialValues`. |
| `cryptography_flutter` | 2.3.4 (checked, **not used**) | It auto-registers native backends through `dartPluginClass: FlutterCryptography` (so merely depending on it switches `Cryptography.instance`), and `FlutterCryptography.enable()` is deprecated. Excluded by the coordinator ruling above. |
| `package_info_plus` / `device_info_plus` | 9.0.1 / 12.4.0 | `PackageInfo.fromPlatform()`, `PackageInfo({appName, packageName, version, buildNumber})` (tests), `.version`, `.buildNumber`; `IosDeviceInfo.modelName`, `AndroidDeviceInfo.manufacturer/model`. |
| `shared_preferences` / `url_launcher` / `app_settings` | 2.5.5 / 6.3.2 / 7.0.0 | `SharedPreferences.getInstance/getBool/setBool/setMockInitialValues`; `launchUrl(uri, mode: LaunchMode.externalApplication)`; `AppSettings.openAppSettings()` (imported with the prefix `system`, because the app has its own `AppSettings`). |

Scratch verification done while writing this plan: the complete app below was built on a copy of the base against the real `shellx_core` and a stub `shellx_client` carrying exactly the overview §5.7 signatures (with the plan 03 behaviour listed above) — `flutter analyze` clean, 334 tests passing, `dart run intl_utils:generate` + `dart run build_runner build` leave no diff, `flutter build apk --debug` and `flutter build ios --simulator --debug` succeed (merged manifest: `package="pro.shellx.mobile"`, `minSdkVersion="26"`, CAMERA/INTERNET/USE_BIOMETRIC; `Runner.app`: `MinimumOSVersion` 15.0, `CFBundleIdentifier` `pro.shellx.mobile`, display name ShellX). The code blocks of this document were then replayed task by task into a fresh workspace: after every task its tests pass, `flutter analyze` is clean and the generated code is fresh, using only the files of that task and the tasks before it; the replayed `apps/mobile` is byte-identical to the verified app. Task 9's code was also checked against the real `shellx_client` of plan 03 Tasks 10–11 (commit `3387ea8` on `feat/shellx-v1-agent-client`): analyze clean, its tests pass.

## File structure

```
apps/mobile/                                 copied from flutter-base/yallabb (Task 1)
  pubspec.yaml, analysis_options.yaml, devtools_options.yaml, .metadata, .gitignore
  assets/fonts/Raleway-*.ttf (base), JetBrainsMono-{Regular,Bold,Italic,BoldItalic}.ttf (Task 1)
  assets/licenses/{JetBrainsMono,Raleway}-OFL.txt (Task 1), assets/icons/*.svg (base)
  android/…  ios/…                           platform config (Task 1)
  docs/state_signal_guide.md                 base
  lib/
    main.dart                                base; font licences registered (Task 19)
    l10n/intl_en.arb, intl_vi.arb            every string (Task 1)
    shared/                                  base widgets; generated S, assets, fonts
      src/app_button.dart, app_text_field.dart (restyled), shellx_logo.dart, status_circle.dart,
          notice_banner.dart, highlighted_text.dart, confirm_dialog.dart (Task 2)
    utils/                                   base validators
    core/
      core.dart                              barrel (grows per task)
      architecture/                          base Controller/StateSignal/errors; error_text.dart (Task 9)
      design/                                tokens from the design; terminal_colors.dart (Task 2)
      dependency/                            get_it + injectable; module.dart (Tasks 1, 3)
      handler/                               base PopupHandler, EventNotifier
      router/                                app_router.dart (Tasks 1, 19), auth_guard.dart, update_guard.dart (Task 19)
      config/app_config.dart, platform/*, settings/app_settings.dart, auth/{account_session,auth_storage}.dart (Task 3)
      backend/backend.dart, client_backend.dart     app-side ports + shellx_client adapter (Task 10)
      auth/{auth_event,session_holder}.dart, version/version_gate.dart (Task 11), auth/session_enforcer.dart (Task 19)
    features/
      app/        app.dart, splash_page.dart (base), launch.dart (Tasks 4, 19), connection_banner.dart (Task 14),
                  update_required_page.dart (Task 18), font_licenses.dart (Task 19)
      lock/       biometric authenticator, AppLockController, LockGate (Task 4)
      terminal/   input (Task 5), extra keys (Tasks 6–7), xterm wrapper (Task 7), metrics + pinch (Task 8),
                  tab controller (Task 12), workspace (Task 13), page (Task 14)
      machines/   last_seen.dart (Task 9), machine list controller (Task 17), page (Task 18)
      pairing/    pairing flow, scanner controller and page (Task 15)
      settings/   settings + delete account (Task 16)
      auth/       validator, controllers, login/register pages (Task 19); PasswordTextField (base, Task 2)
  test/  (mirrors lib/; support/ holds the widget harness, fakes and the scripted relay HTTP API)
```

---

### Task 1: Scaffold `apps/mobile` from the yallabb base — workspace member, identity, platform config, fonts, strings, CI

**Files:**
- Copy: `flutter-base/yallabb` working tree → `apps/mobile/**` (rsync with excludes)
- Delete: the base's demo features, auth/`dio` stack, French strings, README and generated leftovers (list in Step 2)
- Modify: `pubspec.yaml` (repository root, one `workspace:` line), `.github/workflows/ci.yml` (mobile job)
- Rewrite: `apps/mobile/pubspec.yaml`, `apps/mobile/analysis_options.yaml`, `apps/mobile/lib/l10n/intl_en.arb`, `apps/mobile/lib/core/core.dart`, `apps/mobile/lib/core/dependency/dependency.dart`, `apps/mobile/lib/core/dependency/module.dart`, `apps/mobile/lib/core/architecture/controller.dart`, `apps/mobile/lib/core/architecture/error_factory.dart`, `apps/mobile/lib/core/router/app_router.dart`, `apps/mobile/lib/core/router/app_route_observer.dart`, `apps/mobile/ios/Runner/Info.plist`, `apps/mobile/ios/Runner/AppDelegate.swift`, `apps/mobile/ios/Flutter/AppFrameworkInfo.plist`, `apps/mobile/android/app/build.gradle.kts`, `apps/mobile/android/app/src/main/AndroidManifest.xml`, `apps/mobile/android/app/src/main/res/values/styles.xml`, `apps/mobile/android/app/src/main/res/values-night/styles.xml`
- Edit: `apps/mobile/lib/core/handler/event_notifier.dart`, `apps/mobile/lib/core/handler/popup_handler.dart`, `apps/mobile/lib/features/app/app.dart`, `apps/mobile/lib/shared/src/app_button.dart`, `apps/mobile/ios/Podfile`, `apps/mobile/ios/Runner.xcodeproj/project.pbxproj`
- Create: `apps/mobile/lib/l10n/intl_vi.arb`, `apps/mobile/lib/features/app/start_page.dart` (placeholder, deleted in Task 19), `apps/mobile/android/app/src/main/kotlin/pro/shellx/mobile/MainActivity.kt`, `apps/mobile/assets/fonts/JetBrainsMono-{Regular,Bold,Italic,BoldItalic}.ttf`, `apps/mobile/assets/licenses/{JetBrainsMono,Raleway}-OFL.txt`
- Generate: `lib/shared/src/l10n.dart`, `lib/shared/src/intl/messages_{all,en,vi}.dart`, `lib/shared/src/{assets,fonts}.gen.dart`, `lib/core/dependency/dependency.config.dart`, `lib/core/router/app_router.gr.dart`
- Test: `apps/mobile/test/platform_config_test.dart`, `apps/mobile/test/l10n_test.dart`, `apps/mobile/test/support/app_harness.dart` (+ the base's `test/utils/validators/*` kept as they are)

**Interfaces:**
- Consumes: root `pubspec.yaml` workspace and `packages/shellx_core` (plan 02).
- Produces: package `shellx_mobile`; `S` (`package:shellx_mobile/shared/shared.dart`, locales `en`, `vi`, every key of the ARB files below — later tasks use them by name); `FontFamily.jetBrainsMono` (`'JetBrainsMono'`) and `Assets.licenses.jetBrainsMonoOFL`/`ralewayOFL` (`package:shellx_mobile/shared/src/{fonts,assets}.gen.dart`); `Controller.errorFactory` and a `Controller.guard` that shows `AppError.title` (never `toString()`); test helpers `localized(home, {locale, builder})`, `routedApp({open, routes, results, locale})`, `stubRoute(name, {pushed})`, `openPushed(tester)`, constants `vi`/`en` (`test/support/app_harness.dart`).

- [ ] **Step 1: Copy the base and join the workspace**

From the repository root (the base is read-only; nothing below writes to it):

```bash
YALLABB="${YALLABB:-$HOME/Documents/workspace/DigitalUnicorn/flutter-base/yallabb}"
git -C "$YALLABB" rev-parse --short HEAD
mkdir -p apps/mobile
rsync -a \
  --exclude .git --exclude build/ --exclude .dart_tool/ --exclude .idea --exclude .fvm --exclude .fvmrc \
  --exclude pubspec.lock --exclude .vscode --exclude ios/Pods --exclude ios/Podfile.lock \
  --exclude android/.gradle --exclude android/local.properties \
  --exclude 'GeneratedPluginRegistrant.*' --exclude .flutter-plugins-dependencies \
  --exclude ios/Flutter/Generated.xcconfig --exclude ios/Flutter/flutter_export_environment.sh \
  --exclude ios/Flutter/ephemeral --exclude ios/.symlinks \
  "$YALLABB/" apps/mobile/
```

Expected: `2437b6f` (the base commit this plan was verified against; its uncommitted `pubspec.yaml` change does not matter because Step 4 rewrites that file). If the base has moved on, stop and ask the coordinator.

Add `apps/mobile` to the root `pubspec.yaml` — exactly one line under `workspace:` (keep every line other plans added):

```yaml
workspace:
  # …keep every entry added by the other plans (packages/shellx_core, packages/shellx_agent,
  # packages/shellx_client, apps/desktop, …) and add:
  - apps/mobile
```

- [ ] **Step 2: Delete what ShellX does not use**

The demo features, the base's auth feature except its `PasswordTextField`, the `dio`/refresh-token stack (`lib/core/{auth,client,models}`, `RefreshTokenHandler`, the base `AuthGuard`), French strings, docs about the removed auth flow, the base's widget test and feature tests, the manual phone-validator test, `build.yaml` (json_serializable) and the `com/example` Android package (Step 6 creates `pro/shellx/mobile`):

```bash
(cd apps/mobile && rm -rf \
  lib/features/single lib/features/list lib/features/entry_testing \
  lib/features/auth/data lib/features/auth/domain \
  lib/features/auth/presentation/controllers lib/features/auth/presentation/pages \
  lib/core/client lib/core/models lib/core/auth \
  lib/core/handler/refresh_token_handler.dart lib/core/router/auth_guard.dart \
  lib/l10n/intl_fr.arb lib/shared/src/intl/messages_fr.dart \
  test/widget_test.dart test/features test/utils/validators/phone_validator_manual_test.dart \
  docs/auth_flows.md README.md build.yaml \
  android/app/src/main/kotlin/com android/app/src/main/java)
```

Then rename the Dart package in every import:

```bash
grep -rl 'package:yallabb/' apps/mobile/lib apps/mobile/test | xargs perl -pi -e 's#package:yallabb/#package:shellx_mobile/#g'
```

- [ ] **Step 3: Write the platform and identity tests**

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
      expect(project, contains('PRODUCT_BUNDLE_IDENTIFIER = pro.shellx.mobile.RunnerTests;'));
      expect(project, isNot(contains('com.example')));
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
      expect(Directory('android/app/src/main/kotlin/com').existsSync(), isFalse);
      expect(readFile('android/app/src/main/res/values/styles.xml'), contains('Theme.AppCompat'));
      expect(readFile('android/app/src/main/res/values-night/styles.xml'), contains('Theme.AppCompat'));
    });
  });

  test('the base package name is gone from sources and platform files', () {
    const baseName =
        'yalla'
        'bb';
    final roots = ['lib', 'test', 'android', 'ios'].map(Directory.new);
    final offenders = [
      for (final root in roots)
        for (final file in root.listSync(recursive: true).whereType<File>())
          if (RegExp(r'\.(dart|arb|kts|kt|xml|plist|pbxproj|xcconfig|swift|gradle)$').hasMatch(file.path) &&
              file.readAsStringSync().toLowerCase().contains(baseName))
            file.path,
    ];
    expect(offenders, isEmpty);
    expect(readFile('pubspec.yaml'), contains('name: shellx_mobile'));
  });

  test('no dio / refresh-token stack and no native crypto plugin', () {
    final pubspec = readFile('pubspec.yaml');
    for (final package in ['dio', 'awesome_dio_interceptor', 'cryptography_flutter', 'flutter_riverpod']) {
      expect(pubspec, isNot(contains('$package:')), reason: package);
    }
    expect(pubspec, contains('resolution: workspace'));
  });

  test('JetBrains Mono and both OFL licenses are bundled', () {
    for (final style in ['Regular', 'Bold', 'Italic', 'BoldItalic']) {
      expect(File('assets/fonts/JetBrainsMono-$style.ttf').lengthSync(), greaterThan(100000));
    }
    expect(readFile('assets/licenses/JetBrainsMono-OFL.txt'), contains('SIL OPEN FONT LICENSE'));
    expect(readFile('assets/licenses/Raleway-OFL.txt'), contains('SIL Open Font License'));
  });
}
```

`apps/mobile/test/support/app_harness.dart` (the design system + `MaterialApp` wrapper every widget test uses; `routedApp` hosts pages under test in a real auto_route router with stand-in routes):

```dart
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/shared/shared.dart';

const Locale vi = Locale('vi');
const Locale en = Locale('en');

/// [home] inside the base design system (`context.colors`, `context.typo`) and a [MaterialApp]
/// with the ShellX strings, in Vietnamese unless [locale] says otherwise.
Widget localized(Widget home, {Locale locale = vi, TransitionBuilder? builder}) => _designSystem(
  MaterialApp(
    locale: locale,
    builder: builder,
    localizationsDelegates: _delegates,
    supportedLocales: S.delegate.supportedLocales,
    theme: ThemeDataFactory.create(Brightness.light),
    home: home,
  ),
);

/// An auto_route app for page tests. Its start page has an "open" button that pushes [open] and
/// adds what the pushed page pops with to [results]; [routes] holds the pages under test
/// ([XRoute.page]) and stand-ins ([stubRoute]).
Widget routedApp({
  required PageRouteInfo Function() open,
  List<AutoRoute> routes = const [],
  List<Object?>? results,
  Locale locale = vi,
}) {
  final router = _TestRouter([
    AutoRoute(page: PageInfo('HostRoute', builder: (_) => _Host(open, results)), initial: true),
    ...routes,
  ]);
  final config = router.config();
  return _designSystem(
    MaterialApp.router(
      locale: locale,
      localizationsDelegates: _delegates,
      supportedLocales: S.delegate.supportedLocales,
      theme: ThemeDataFactory.create(Brightness.light),
      routerConfig: config,
    ),
  );
}

/// A route named [name] (e.g. `TerminalRoute.name`) that only shows "[name] stub" with a back
/// button, and records the arguments it was pushed with in [pushed].
AutoRoute stubRoute(String name, {List<Object?>? pushed}) => AutoRoute(
  page: PageInfo(
    name,
    builder: (data) {
      pushed?.add(data.args);
      return Scaffold(appBar: AppBar(title: Text('$name stub')));
    },
  ),
);

/// Taps the start page's "open" button of [routedApp] and settles.
Future<void> openPushed(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

class _TestRouter extends RootStackRouter {
  _TestRouter(this.routes);

  @override
  final List<AutoRoute> routes;
}

class _Host extends StatelessWidget {
  const _Host(this.open, this.results);

  final PageRouteInfo Function() open;
  final List<Object?>? results;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () async {
          final result = await context.router.push<Object?>(open());
          results?.add(result);
        },
        child: const Text('open'),
      ),
    ),
  );
}

const List<LocalizationsDelegate<dynamic>> _delegates = [
  S.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

Widget _designSystem(Widget child) => DesignSystem(
  typography: AppTypography.instance,
  appColors: Brightness.light.appColors,
  brightness: Brightness.light,
  child: child,
);
```

`apps/mobile/test/l10n_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/shared/shared.dart';

import 'support/app_harness.dart';

Set<String> messageKeys(String path) {
  final json = jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
  return json.keys.where((key) => !key.startsWith('@')).toSet();
}

void main() {
  test('Vietnamese and English ARB files define the same messages', () {
    expect(messageKeys('lib/l10n/intl_vi.arb'), messageKeys('lib/l10n/intl_en.arb'));
  });

  test('the generated strings are fresh: every ARB key has a getter in S', () {
    final generated = File('lib/shared/src/l10n.dart').readAsStringSync();
    for (final key in messageKeys('lib/l10n/intl_en.arb')) {
      expect(generated, contains("name: '$key'"), reason: key);
    }
  });

  test('exactly English and Vietnamese are supported', () {
    expect(S.delegate.supportedLocales.map((locale) => locale.languageCode), unorderedEquals(['en', 'vi']));
  });

  test('spec texts and plurals in both languages', () async {
    final vi = await S.load(const Locale('vi'));
    expect(vi.bannerReconnecting, 'Mất kết nối, đang thử lại…');
    expect(vi.lastSeenMinutes(5), '5 phút trước');
    final en = await S.load(const Locale('en'));
    expect(en.bannerReconnecting, 'Connection lost, retrying…');
    expect(en.lastSeenMinutes(1), '1 minute ago');
    expect(en.lastSeenMinutes(5), '5 minutes ago');
  });

  testWidgets('S.of(context) resolves Vietnamese inside the design system', (tester) async {
    await tester.pumpWidget(localized(Builder(builder: (context) => Text(S.of(context).machinesTitle))));
    await tester.pumpAndSettle();
    expect(find.text('Máy của bạn'), findsOneWidget);
  });
}
```

- [ ] **Step 4: Rewrite `pubspec.yaml` and `analysis_options.yaml`**

`apps/mobile/pubspec.yaml` (replace the whole file; `shellx_client` joins in Task 9):

```yaml
name: shellx_mobile
description: "ShellX mobile app: control your computer's terminal from your phone."
publish_to: 'none'
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

  # Team base (flutter-base/yallabb)
  adaptive_theme: ^3.7.2
  async: ^2.13.0
  auto_route: 11.1.0
  cupertino_icons: ^1.0.8
  easy_refresh: ^3.4.0
  equatable: ^2.0.8
  flutter_secure_storage: ^10.3.4
  flutter_svg: ^2.2.3
  get_it: ^9.2.0
  injectable: ^2.7.1+4
  intl: ^0.20.2
  shared_preferences: ^2.5.5
  signals_flutter: ^6.3.0
  sliver_tools: ^0.2.12
  toastification: ^3.0.3
  universal_back_gesture: ^2.1.0

  # ShellX
  app_settings: 7.0.0
  device_info_plus: ^12.3.0
  local_auth: ^3.0.2
  mobile_scanner: ^7.4.2
  package_info_plus: ^9.0.1
  shellx_core: any
  url_launcher: ^6.3.2
  xterm: ^4.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter

  fake_async: ^1.3.3
  flutter_lints: ^6.0.0
  http: ^1.6.0
  shared_preferences_platform_interface: ^2.4.1

  # Code generators, pinned exactly: their output is committed and CI checks it is fresh.
  auto_route_generator: 10.5.0
  build_runner: 2.15.1
  dart_style: 3.1.7
  flutter_gen_runner: 5.15.0
  injectable_generator: 2.12.1
  intl_utils: 2.8.14

flutter:
  generate: true
  uses-material-design: true

  assets:
    - assets/icons/
    - assets/licenses/

  fonts:
    # UI font of the team base, SIL OFL 1.1: assets/licenses/Raleway-OFL.txt
    - family: Raleway
      fonts:
        - asset: assets/fonts/Raleway-Black.ttf
          weight: 900
        - asset: assets/fonts/Raleway-BlackItalic.ttf
          weight: 900
          style: italic
        - asset: assets/fonts/Raleway-Bold.ttf
          weight: 700
        - asset: assets/fonts/Raleway-BoldItalic.ttf
          weight: 700
          style: italic
        - asset: assets/fonts/Raleway-ExtraBold.ttf
          weight: 800
        - asset: assets/fonts/Raleway-ExtraBoldItalic.ttf
          weight: 800
          style: italic
        - asset: assets/fonts/Raleway-ExtraLight.ttf
          weight: 200
        - asset: assets/fonts/Raleway-ExtraLightItalic.ttf
          weight: 200
          style: italic
        - asset: assets/fonts/Raleway-Italic.ttf
          style: italic
        - asset: assets/fonts/Raleway-Light.ttf
          weight: 300
        - asset: assets/fonts/Raleway-LightItalic.ttf
          weight: 300
          style: italic
        - asset: assets/fonts/Raleway-Medium.ttf
          weight: 500
        - asset: assets/fonts/Raleway-MediumItalic.ttf
          weight: 500
          style: italic
        - asset: assets/fonts/Raleway-Regular.ttf
        - asset: assets/fonts/Raleway-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/Raleway-SemiBoldItalic.ttf
          weight: 600
          style: italic
        - asset: assets/fonts/Raleway-Thin.ttf
          weight: 100
        - asset: assets/fonts/Raleway-ThinItalic.ttf
          weight: 100
          style: italic
    # Terminal font (spec §9.1), SIL OFL 1.1: assets/licenses/JetBrainsMono-OFL.txt
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

flutter_gen:
  output: lib/shared/src/
  line_length: 120
  integrations:
    flutter_svg: true

flutter_intl:
  enabled: true
  output_dir: lib/shared/src/
```

`apps/mobile/analysis_options.yaml` (the base's file plus `page_width: 120`, which the base code is already formatted to):

```yaml
# This file configures the analyzer, which statically analyzes Dart code to
# check for errors, warnings, and lints.
#
# The issues identified by the analyzer are surfaced in the UI of Dart-enabled
# IDEs (https://dart.dev/tools#ides-and-editors). The analyzer can also be
# invoked from the command line by running `flutter analyze`.

# The following line activates a set of recommended lints for Flutter apps,
# packages, and plugins designed to encourage good coding practices.
include: package:flutter_lints/flutter.yaml

formatter:
    page_width: 120
    trailing_commas: preserve

analyzer:
  exclude:
    - "lib/shared/src/intl/**"

linter:
 
  rules:
    avoid_print: false  # Uncomment to disable the `avoid_print` rule
    prefer_single_quotes: true  # Uncomment to enable the `prefer_single_quotes` rule
    
```

Resolve the workspace from the repository root:

```bash
flutter pub get
```

Expected: `Got dependencies!` with `auto_route 11.1.0`, `device_info_plus 12.4.0`, `flutter_secure_storage 10.3.4`, `signals_flutter 6.3.1`, `test 1.30.0` in `pubspec.lock`.

- [ ] **Step 5: Run the new tests to see them fail**

Run: `cd apps/mobile && flutter test test/platform_config_test.dart test/l10n_test.dart`
Expected: FAIL — `l10n_test.dart` does not compile (`S` has no `bannerReconnecting`, `lib/core/core.dart` still exports deleted files), and `platform_config_test.dart` fails on the iOS deployment target, bundle id, Android ids and missing fonts.

- [ ] **Step 6: Platform configuration — identity, iOS 15, Android 8, permissions, no backup**

iOS deployment target and bundle identifier:

```bash
perl -pi -e "s/^# platform :ios, '13.0'/platform :ios, '15.0'/" apps/mobile/ios/Podfile
perl -pi -e 's/IPHONEOS_DEPLOYMENT_TARGET = 13\.0;/IPHONEOS_DEPLOYMENT_TARGET = 15.0;/g; s/com\.example\.yallabb/pro.shellx.mobile/g' \
  apps/mobile/ios/Runner.xcodeproj/project.pbxproj
```

`apps/mobile/ios/Runner/Info.plist` (display name, both UI languages, camera and Face ID texts, `https` for `url_launcher`, and the UIScene manifest that Flutter 3.41 migrates to):

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
					<string>FlutterSceneDelegate</string>
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

`apps/mobile/ios/Runner/AppDelegate.swift` (the UIScene form Flutter 3.41 generates; plugins register on the implicit engine):

```swift
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
```

`apps/mobile/ios/Flutter/AppFrameworkInfo.plist` (Flutter 3.41 drops `MinimumOSVersion` here; the project's deployment target rules):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>App</string>
  <key>CFBundleIdentifier</key>
  <string>io.flutter.flutter.app</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>App</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleSignature</key>
  <string>????</string>
  <key>CFBundleVersion</key>
  <string>1.0</string>
</dict>
</plist>
```

`apps/mobile/android/app/build.gradle.kts`:

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
            // Release signing is configured by the store release process.
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

`apps/mobile/android/app/src/main/AndroidManifest.xml`:

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
            <!-- Specifies an Android theme to apply to this Activity as soon as
                 the Android process has started. This theme is visible to the user
                 while the Flutter UI initializes. After that, this theme continues
                 to determine the Window background behind the Flutter UI. -->
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
    <!-- Required to query activities that can process text, see:
         https://developer.android.com/training/package-visibility and
         https://developer.android.com/reference/android/content/Intent#ACTION_PROCESS_TEXT.

         In particular, this is used by the Flutter engine in io.flutter.plugin.text.ProcessTextPlugin.
         The https VIEW query lets url_launcher open the download page. -->
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

`apps/mobile/android/app/src/main/kotlin/pro/shellx/mobile/MainActivity.kt`:

```kotlin
package pro.shellx.mobile

import io.flutter.embedding.android.FlutterFragmentActivity

// local_auth shows BiometricPrompt, which needs a FragmentActivity.
class MainActivity : FlutterFragmentActivity()
```

`apps/mobile/android/app/src/main/res/values/styles.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- AppCompat parents are required by local_auth (BiometricPrompt) on Android 8. -->
    <!-- Theme applied to the Android Window while the process is starting when the OS's Dark Mode setting is off -->
    <style name="LaunchTheme" parent="Theme.AppCompat.Light.NoActionBar">
        <!-- Show a splash screen on the activity. Automatically removed when
             the Flutter engine draws its first frame -->
        <item name="android:windowBackground">@drawable/launch_background</item>
    </style>
    <!-- Theme applied to the Android Window as soon as the process has started.
         This theme determines the color of the Android Window while your
         Flutter UI initializes, as well as behind your Flutter UI while its
         running.

         This Theme is only used starting with V2 of Flutter's Android embedding. -->
    <style name="NormalTheme" parent="Theme.AppCompat.Light.NoActionBar">
        <item name="android:windowBackground">?android:colorBackground</item>
    </style>
</resources>
```

`apps/mobile/android/app/src/main/res/values-night/styles.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- AppCompat parents are required by local_auth (BiometricPrompt) on Android 8. -->
    <!-- Theme applied to the Android Window while the process is starting when the OS's Dark Mode setting is on -->
    <style name="LaunchTheme" parent="Theme.AppCompat.NoActionBar">
        <!-- Show a splash screen on the activity. Automatically removed when
             the Flutter engine draws its first frame -->
        <item name="android:windowBackground">@drawable/launch_background</item>
    </style>
    <!-- Theme applied to the Android Window as soon as the process has started.
         This theme determines the color of the Android Window while your
         Flutter UI initializes, as well as behind your Flutter UI while its
         running.

         This Theme is only used starting with V2 of Flutter's Android embedding. -->
    <style name="NormalTheme" parent="Theme.AppCompat.NoActionBar">
        <item name="android:windowBackground">?android:colorBackground</item>
    </style>
</resources>
```

- [ ] **Step 7: Bundle JetBrains Mono and both font licences (SIL Open Font License 1.1)**

The Raleway TTFs came with the base; its licence and JetBrains Mono (official release `v2.304`, <https://github.com/JetBrains/JetBrainsMono/releases/tag/v2.304>) are added here. Both licences are registered with `LicenseRegistry` in Task 19. From the repository root:

```bash
mkdir -p apps/mobile/assets/licenses
curl -fsSL -o "${TMPDIR:-/tmp}/JetBrainsMono-2.304.zip" \
  https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip
echo "6f6376c6ed2960ea8a963cd7387ec9d76e3f629125bc33d1fdcd7eb7012f7bbf  ${TMPDIR:-/tmp}/JetBrainsMono-2.304.zip" | shasum -a 256 -c -
unzip -o -j "${TMPDIR:-/tmp}/JetBrainsMono-2.304.zip" \
  fonts/ttf/JetBrainsMono-Regular.ttf fonts/ttf/JetBrainsMono-Bold.ttf \
  fonts/ttf/JetBrainsMono-Italic.ttf fonts/ttf/JetBrainsMono-BoldItalic.ttf \
  -d apps/mobile/assets/fonts
unzip -p "${TMPDIR:-/tmp}/JetBrainsMono-2.304.zip" OFL.txt > apps/mobile/assets/licenses/JetBrainsMono-OFL.txt
curl -fsSL -o apps/mobile/assets/licenses/Raleway-OFL.txt \
  https://raw.githubusercontent.com/google/fonts/37a6dd7a5aef8e3fc8df3435a35a72312e556811/ofl/raleway/OFL.txt
echo "7e946cf1171784d1015279e7dc35f827957a6b5d1f1f659ae0c98e5f5e37ed9b  apps/mobile/assets/licenses/Raleway-OFL.txt" | shasum -a 256 -c -
ls -l apps/mobile/assets/fonts/JetBrainsMono-* apps/mobile/assets/licenses
```

Expected: both `shasum` lines print `OK`; four TTFs of 273–280 KB, `JetBrainsMono-OFL.txt` 4399 bytes, `Raleway-OFL.txt` 4497 bytes.

- [ ] **Step 8: Write every user-visible string (English + Vietnamese)**

The base's messages that `lib/core/architecture/error.dart`, `lib/shared` and `lib/utils` use are kept (the unused `hello` goes); every ShellX string of the approved design is added now so later tasks only use keys. Vietnamese texts are the spec's and the design's, verbatim.

`apps/mobile/lib/l10n/intl_en.arb` (replace the whole file):

```json
{
  "@@locale": "en",
  "somethingWentWrong": "Something went wrong",
  "loadMoreFailPleaseTryAgain": "Load more failed\nPlease try again",
  "retry": "Retry",
  "somethingWentWrongPleaseTryAgain": "Something went wrong, please try again",
  "forbiddenTitle": "You don't have permission to access this feature",
  "networkError": "Network Error",
  "notFound": "Not Found",
  "unauthorized": "Unauthorized",
  "unknownError": "Unknown Error",
  "validationEmailRequired": "Email is required",
  "validationEmailInvalid": "Please enter a valid email address",
  "validationPasswordRequired": "Password is required",
  "validationPasswordMinLength": "Password must be at least {length} characters",
  "@validationPasswordMinLength": {
    "placeholders": {
      "length": {
        "type": "int"
      }
    }
  },
  "validationPasswordUppercase": "Password must contain at least one uppercase letter",
  "validationPasswordLowercase": "Password must contain at least one lowercase letter",
  "validationPasswordDigit": "Password must contain at least one number",
  "validationPasswordSpecialChar": "Password must contain at least one special character",
  "validationPasswordConfirmRequired": "Please confirm your password",
  "validationPasswordNotMatch": "Passwords do not match",
  "validationTextRequired": "This field is required",
  "validationTextMinLength": "Must be at least {length} characters",
  "@validationTextMinLength": {
    "placeholders": {
      "length": {
        "type": "int"
      }
    }
  },
  "validationTextMaxLength": "Must be at most {length} characters",
  "@validationTextMaxLength": {
    "placeholders": {
      "length": {
        "type": "int"
      }
    }
  },
  "validationPhoneRequired": "Phone number is required",
  "validationPhoneInvalid": "Please enter a valid phone number",
  "appTitle": "ShellX",
  "actionCancel": "Cancel",
  "actionClose": "Close",
  "actionLater": "Later",
  "loginTitle": "Sign in",
  "loginSubtitle": "Use the same account as ShellX on your computer.",
  "emailLabel": "Email",
  "emailHint": "email@example.com",
  "passwordLabel": "Password",
  "passwordHint": "Password",
  "loginButton": "Sign in",
  "forgotPasswordHint": "Forgot your password? Change it in ShellX on a computer that is signed in.",
  "noAccountPrompt": "No account yet?",
  "createAccountLink": "Create one",
  "signedOutExpired": "Your sign-in has expired. Please sign in again.",
  "signedOutAccountDeleted": "Your account has been deleted.",
  "registerTitle": "Create account",
  "registerSubtitle": "One account for your phone and all your computers.",
  "registerButton": "Create account",
  "passwordRule": "8 to 128 characters.",
  "passwordMissing": "{count, plural, =1{1 more character needed.} other{{count} more characters needed.}}",
  "@passwordMissing": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "passwordTooLong": "{count, plural, =1{1 character too many.} other{{count} characters too many.}}",
  "@passwordTooLong": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "termsNotice": "By creating an account you agree to the {terms} and the {privacy}.",
  "@termsNotice": {
    "placeholders": {
      "terms": {
        "type": "String"
      },
      "privacy": {
        "type": "String"
      }
    }
  },
  "termsLink": "Terms",
  "privacyLink": "Privacy Policy",
  "errorInvalidEmail": "Invalid email address.",
  "errorWeakPassword": "Password must be 8–128 characters.",
  "errorDisposableEmail": "Disposable email addresses can't be used. Please use a real email.",
  "errorEmailTaken": "This email is already registered.",
  "errorInvalidCredentials": "Incorrect email or password.",
  "errorWrongPassword": "Incorrect password.",
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
  "updateRequiredBody": "This version can no longer connect to your computers. Update to keep using ShellX.",
  "openAppStore": "Open the App Store",
  "openPlayStore": "Open Google Play",
  "lockTitle": "ShellX is locked",
  "lockSubtitle": "Unlock to see your computers and terminal sessions.",
  "lockReason": "Unlock ShellX",
  "lockUnlockWith": "Unlock with {method}",
  "@lockUnlockWith": {
    "placeholders": {
      "method": {
        "type": "String"
      }
    }
  },
  "biometricFaceId": "Face ID",
  "biometricTouchId": "Touch ID",
  "biometricFingerprint": "fingerprint",
  "biometricGeneric": "biometrics",
  "biometricPasscode": "device passcode",
  "bannerReconnecting": "Connection lost, retrying…",
  "bannerReplaced": "Another instance of the app has connected.",
  "bannerReconnectButton": "Reconnect",
  "machinesTitle": "Your computers",
  "settingsTooltip": "Settings",
  "machineOnline": "Online",
  "machinesOfflineHeader": "Offline",
  "machineOffline": "This computer is offline.",
  "machineWaiting": "Waiting for connection",
  "machineLastOnline": "Last online: {when}",
  "@machineLastOnline": {
    "placeholders": {
      "when": {
        "type": "String"
      }
    }
  },
  "machineNotPaired": "Not paired",
  "machineTabs": "{count, plural, =1{1 tab} other{{count} tabs}}",
  "@machineTabs": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "pairNewMachine": "Pair a new computer",
  "emptyTitle": "No computers yet",
  "emptyStep1": "Install ShellX on your computer (macOS or Windows) from {site}.",
  "@emptyStep1": {
    "placeholders": {
      "site": {
        "type": "String"
      }
    }
  },
  "emptyStep2": "Sign in with this same account.",
  "emptyStep3": "Click the ShellX icon → {menu}, then scan the code.",
  "@emptyStep3": {
    "placeholders": {
      "menu": {
        "type": "String"
      }
    }
  },
  "pairPhoneMenuItem": "Pair phone…",
  "scanQrButton": "Scan QR code",
  "untrustedTitle": "Pair again",
  "actionScanCode": "Scan code",
  "lastSeenJustNow": "just now",
  "lastSeenMinutes": "{count, plural, =1{1 minute ago} other{{count} minutes ago}}",
  "@lastSeenMinutes": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "lastSeenToday": "today, {time}",
  "@lastSeenToday": {
    "placeholders": {
      "time": {
        "type": "String"
      }
    }
  },
  "lastSeenYesterday": "yesterday, {time}",
  "@lastSeenYesterday": {
    "placeholders": {
      "time": {
        "type": "String"
      }
    }
  },
  "lastSeenDate": "{month}/{day}, {time}",
  "@lastSeenDate": {
    "placeholders": {
      "day": {
        "type": "int"
      },
      "month": {
        "type": "int"
      },
      "time": {
        "type": "String"
      }
    }
  },
  "lastSeenUnknown": "unknown",
  "scannerTitle": "Scan pairing code",
  "scannerCardTitle": "The code is on your computer",
  "scannerCardBody": "macOS: click the ShellX icon in the menu bar. Windows: click the icon in the system tray. Choose {menu}",
  "@scannerCardBody": {
    "placeholders": {
      "menu": {
        "type": "String"
      }
    }
  },
  "scannerPairing": "Pairing…",
  "scannerCameraDenied": "Camera access is needed to scan the QR code. Allow it in your phone's Settings.",
  "openSettings": "Open Settings",
  "scannerCameraError": "Couldn't start the camera.",
  "pairingSucceeded": "Paired",
  "pairingSucceededBody": "{name} now trusts this phone. From now on, just tap the computer to open a terminal.",
  "@pairingSucceededBody": {
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "openTerminal": "Open terminal",
  "backToMachines": "Back to computers",
  "pairingFailedTitle": "Couldn't pair",
  "scanAgain": "Scan again",
  "terminalConnected": "Connected · end-to-end encrypted",
  "terminalConnecting": "Connecting…",
  "fontSizeTooltip": "Font size",
  "keyboardTooltip": "Keyboard",
  "terminalOpenNew": "Open a new session",
  "terminalCloseTab": "Close session",
  "terminalCloseConfirm": "Close this session? Programs running in it will be stopped.",
  "terminalNoTabs": "No open sessions.",
  "sessionsLoading": "Getting the session list…",
  "pickerTitle": "{count, plural, =1{This computer has 1 session} other{This computer has {count} sessions}}",
  "@pickerTitle": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "pickerSubtitle": "Reopen a session to continue where you left off, or start a new one.",
  "pickerOpen": "Open",
  "pickerStarted": "opened {when}",
  "@pickerStarted": {
    "placeholders": {
      "when": {
        "type": "String"
      }
    }
  },
  "pickerAttachedElsewhere": "open on another device",
  "sessionEnded": "Session ended",
  "sessionExitedBody": "The last command exited with code {code}. The output above can still be read and copied.",
  "@sessionExitedBody": {
    "placeholders": {
      "code": {
        "type": "int"
      }
    }
  },
  "sessionGoneBody": "The computer no longer has this session. The output above can still be read and copied.",
  "tabTakenOver": "This session was opened on another device.",
  "tabClosedByHost": "The session was closed on the computer.",
  "tabReattach": "Reattach",
  "closeTab": "Close tab",
  "copyAction": "Copy",
  "copied": "Copied",
  "keyPaste": "Paste",
  "settingsTitle": "Settings",
  "settingsTerminalGroup": "Terminal",
  "settingsFontSize": "Default font size",
  "settingsSecurityGroup": "Security",
  "settingsLockWith": "Lock with {method}",
  "@settingsLockWith": {
    "placeholders": {
      "method": {
        "type": "String"
      }
    }
  },
  "settingsLockFootnote": "Asked when the app opens and when you come back after more than 5 minutes.",
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
  "settingsAccountGroup": "Account",
  "settingsEmail": "Email",
  "settingsLogout": "Sign out",
  "settingsLogoutConfirm": "Sign out of ShellX? Paired computers are kept for your next sign-in.",
  "settingsDeleteAccount": "Delete account",
  "settingsVersion": "ShellX {version} ({build})",
  "@settingsVersion": {
    "placeholders": {
      "version": {
        "type": "String"
      },
      "build": {
        "type": "String"
      }
    }
  },
  "unknownMachine": "Unknown computer",
  "deleteAccountTitle": "Delete account",
  "deleteAccountWarningTitle": "This can't be undone",
  "deleteAccountLoseAccount": "Deletes the account {email} with all its devices and pairings.",
  "@deleteAccountLoseAccount": {
    "placeholders": {
      "email": {
        "type": "String"
      }
    }
  },
  "deleteAccountLoseComputers": "Every computer signed in to it is signed out.",
  "deleteAccountLoseSessions": "Open terminal sessions are closed.",
  "deleteAccountPasswordLabel": "Enter your password to confirm",
  "deleteAccountButton": "Delete permanently"
}
```

`apps/mobile/lib/l10n/intl_vi.arb`:

```json
{
  "@@locale": "vi",
  "somethingWentWrong": "Đã có lỗi xảy ra",
  "loadMoreFailPleaseTryAgain": "Tải thêm thất bại\nHãy thử lại",
  "retry": "Thử lại",
  "somethingWentWrongPleaseTryAgain": "Đã có lỗi xảy ra, hãy thử lại",
  "forbiddenTitle": "Bạn không có quyền dùng chức năng này",
  "networkError": "Lỗi mạng",
  "notFound": "Không tìm thấy",
  "unauthorized": "Chưa được xác thực",
  "unknownError": "Lỗi không xác định",
  "validationEmailRequired": "Cần nhập email",
  "validationEmailInvalid": "Hãy nhập địa chỉ email hợp lệ",
  "validationPasswordRequired": "Cần nhập mật khẩu",
  "validationPasswordMinLength": "Mật khẩu phải có ít nhất {length} ký tự",
  "validationPasswordUppercase": "Mật khẩu phải có ít nhất một chữ hoa",
  "validationPasswordLowercase": "Mật khẩu phải có ít nhất một chữ thường",
  "validationPasswordDigit": "Mật khẩu phải có ít nhất một chữ số",
  "validationPasswordSpecialChar": "Mật khẩu phải có ít nhất một ký tự đặc biệt",
  "validationPasswordConfirmRequired": "Hãy xác nhận mật khẩu",
  "validationPasswordNotMatch": "Mật khẩu không khớp",
  "validationTextRequired": "Trường này là bắt buộc",
  "validationTextMinLength": "Phải có ít nhất {length} ký tự",
  "validationTextMaxLength": "Tối đa {length} ký tự",
  "validationPhoneRequired": "Cần nhập số điện thoại",
  "validationPhoneInvalid": "Hãy nhập số điện thoại hợp lệ",
  "appTitle": "ShellX",
  "actionCancel": "Hủy",
  "actionClose": "Đóng",
  "actionLater": "Để sau",
  "loginTitle": "Đăng nhập",
  "loginSubtitle": "Dùng cùng tài khoản với ShellX trên máy tính.",
  "emailLabel": "Email",
  "emailHint": "email@example.com",
  "passwordLabel": "Mật khẩu",
  "passwordHint": "Mật khẩu",
  "loginButton": "Đăng nhập",
  "forgotPasswordHint": "Quên mật khẩu? Đổi mật khẩu trong ShellX trên máy tính đang đăng nhập.",
  "noAccountPrompt": "Chưa có tài khoản?",
  "createAccountLink": "Tạo tài khoản",
  "signedOutExpired": "Phiên đăng nhập đã hết hiệu lực. Hãy đăng nhập lại.",
  "signedOutAccountDeleted": "Tài khoản đã được xóa.",
  "registerTitle": "Tạo tài khoản",
  "registerSubtitle": "Một tài khoản cho điện thoại và mọi máy tính của bạn.",
  "registerButton": "Tạo tài khoản",
  "passwordRule": "Từ 8 đến 128 ký tự.",
  "passwordMissing": "{count, plural, other{Còn thiếu {count} ký tự.}}",
  "passwordTooLong": "{count, plural, other{Thừa {count} ký tự.}}",
  "termsNotice": "Khi tạo tài khoản, bạn đồng ý với {terms} và {privacy}.",
  "termsLink": "Điều khoản",
  "privacyLink": "Chính sách quyền riêng tư",
  "errorInvalidEmail": "Email không hợp lệ.",
  "errorWeakPassword": "Mật khẩu phải có 8–128 ký tự.",
  "errorDisposableEmail": "Email tạm thời không dùng được. Hãy dùng email thật.",
  "errorEmailTaken": "Email này đã được đăng ký.",
  "errorInvalidCredentials": "Email hoặc mật khẩu không đúng.",
  "errorWrongPassword": "Mật khẩu không đúng.",
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
  "updateRequiredBody": "Phiên bản này không còn kết nối được với máy của bạn. Cập nhật để dùng tiếp.",
  "openAppStore": "Mở App Store",
  "openPlayStore": "Mở Google Play",
  "lockTitle": "ShellX đang khóa",
  "lockSubtitle": "Mở khóa để xem các máy và phiên terminal của bạn.",
  "lockReason": "Mở khóa ShellX",
  "lockUnlockWith": "Mở khóa bằng {method}",
  "biometricFaceId": "Face ID",
  "biometricTouchId": "Touch ID",
  "biometricFingerprint": "vân tay",
  "biometricGeneric": "sinh trắc học",
  "biometricPasscode": "mã máy",
  "bannerReconnecting": "Mất kết nối, đang thử lại…",
  "bannerReplaced": "Một phiên bản khác của app đã kết nối.",
  "bannerReconnectButton": "Kết nối lại",
  "machinesTitle": "Máy của bạn",
  "settingsTooltip": "Cài đặt",
  "machineOnline": "Online",
  "machinesOfflineHeader": "Offline",
  "machineOffline": "Máy đang offline.",
  "machineWaiting": "Đang chờ kết nối",
  "machineLastOnline": "Lần cuối online: {when}",
  "machineNotPaired": "Chưa ghép nối",
  "machineTabs": "{count, plural, other{{count} tab}}",
  "pairNewMachine": "Ghép nối máy mới",
  "emptyTitle": "Chưa có máy nào",
  "emptyStep1": "Cài ShellX trên máy tính (macOS hoặc Windows) từ {site}.",
  "emptyStep2": "Đăng nhập cùng tài khoản này.",
  "emptyStep3": "Bấm biểu tượng ShellX → {menu}, rồi quét mã.",
  "pairPhoneMenuItem": "Ghép nối điện thoại…",
  "scanQrButton": "Quét mã QR",
  "untrustedTitle": "Cần ghép nối lại",
  "actionScanCode": "Quét mã",
  "lastSeenJustNow": "vừa xong",
  "lastSeenMinutes": "{count, plural, other{{count} phút trước}}",
  "lastSeenToday": "hôm nay, {time}",
  "lastSeenYesterday": "hôm qua, {time}",
  "lastSeenDate": "{day}/{month}, {time}",
  "lastSeenUnknown": "không rõ",
  "scannerTitle": "Quét mã ghép nối",
  "scannerCardTitle": "Mã nằm trên máy tính của bạn",
  "scannerCardBody": "macOS: bấm biểu tượng ShellX trên thanh menu. Windows: bấm biểu tượng ở khay hệ thống. Chọn {menu}",
  "scannerPairing": "Đang ghép nối…",
  "scannerCameraDenied": "Cần quyền camera để quét mã QR. Hãy cho phép trong Cài đặt của điện thoại.",
  "openSettings": "Mở Cài đặt",
  "scannerCameraError": "Không mở được camera.",
  "pairingSucceeded": "Đã ghép nối",
  "pairingSucceededBody": "{name} đã tin cậy điện thoại này. Từ giờ chỉ cần chạm vào máy để mở terminal.",
  "openTerminal": "Mở terminal",
  "backToMachines": "Về danh sách máy",
  "pairingFailedTitle": "Không ghép nối được",
  "scanAgain": "Quét lại",
  "terminalConnected": "Đã kết nối · mã hóa đầu cuối",
  "terminalConnecting": "Đang kết nối…",
  "fontSizeTooltip": "Cỡ chữ",
  "keyboardTooltip": "Bàn phím",
  "terminalOpenNew": "Mở phiên mới",
  "terminalCloseTab": "Đóng phiên",
  "terminalCloseConfirm": "Đóng phiên này? Mọi chương trình đang chạy trong phiên sẽ bị dừng.",
  "terminalNoTabs": "Chưa có phiên nào đang mở.",
  "sessionsLoading": "Đang lấy danh sách phiên…",
  "pickerTitle": "{count, plural, other{Máy này đang có {count} phiên}}",
  "pickerSubtitle": "Mở lại phiên cũ để xem tiếp đúng chỗ đã dừng, hoặc tạo phiên mới.",
  "pickerOpen": "Mở",
  "pickerStarted": "mở {when}",
  "pickerAttachedElsewhere": "đang mở trên thiết bị khác",
  "sessionEnded": "Phiên đã kết thúc",
  "sessionExitedBody": "Lệnh cuối thoát với mã {code}. Nội dung ở trên vẫn đọc và copy được.",
  "sessionGoneBody": "Máy tính không còn phiên này. Nội dung ở trên vẫn đọc và copy được.",
  "tabTakenOver": "Phiên đang được mở trên thiết bị khác.",
  "tabClosedByHost": "Phiên đã bị đóng trên máy tính.",
  "tabReattach": "Gắn lại",
  "closeTab": "Đóng tab",
  "copyAction": "Sao chép",
  "copied": "Đã sao chép",
  "keyPaste": "Dán",
  "settingsTitle": "Cài đặt",
  "settingsTerminalGroup": "Terminal",
  "settingsFontSize": "Cỡ chữ mặc định",
  "settingsSecurityGroup": "Bảo mật",
  "settingsLockWith": "Khóa bằng {method}",
  "settingsLockFootnote": "Hỏi khi mở app và khi quay lại sau hơn 5 phút.",
  "settingsBiometricUnavailable": "Thiết bị chưa đặt mã khóa hoặc sinh trắc học",
  "settingsPairedMachines": "Máy đã ghép nối",
  "settingsNoPairedMachines": "Chưa ghép nối máy nào.",
  "settingsUnpair": "Bỏ ghép nối",
  "settingsUnpairConfirm": "Bỏ ghép nối {name}? Bạn sẽ phải quét lại mã QR để dùng máy này.",
  "settingsAccountGroup": "Tài khoản",
  "settingsEmail": "Email",
  "settingsLogout": "Đăng xuất",
  "settingsLogoutConfirm": "Đăng xuất khỏi ShellX? Các máy đã ghép nối vẫn được giữ cho lần đăng nhập sau.",
  "settingsDeleteAccount": "Xóa tài khoản",
  "settingsVersion": "ShellX {version} ({build})",
  "unknownMachine": "Máy không xác định",
  "deleteAccountTitle": "Xóa tài khoản",
  "deleteAccountWarningTitle": "Không hoàn tác được",
  "deleteAccountLoseAccount": "Xóa tài khoản {email}, mọi máy và mọi ghép nối.",
  "deleteAccountLoseComputers": "Mọi máy tính đang đăng nhập sẽ bị đăng xuất.",
  "deleteAccountLoseSessions": "Phiên terminal đang mở sẽ đóng.",
  "deleteAccountPasswordLabel": "Nhập mật khẩu để xác nhận",
  "deleteAccountButton": "Xóa vĩnh viễn"
}
```

- [ ] **Step 9: Strip the base core down to what ShellX uses**

`apps/mobile/lib/core/core.dart` (replace the whole file — the auth, client and model exports go; later tasks add ShellX exports):

```dart
export 'dependency/dependency.dart';
export 'design/app_colors.dart';
export 'design/dark_colors.dart';
export 'design/light_colors.dart';
export 'design/typography.dart';
export 'design/design_system.dart';
export 'design/theme_data_factory.dart';
export 'extensions/adaptive_theme_mode_x.dart';
export 'router/app_router.dart';
export 'architecture/error.dart';
export 'architecture/error_factory.dart';
export 'architecture/controller.dart';
export 'architecture/state_signal.dart';
export 'handler/popup_handler.dart';
export 'architecture/page_domain.dart';
export 'architecture/paging_state_signal.dart';
export 'architecture/state.dart';
export 'router/app_router.gr.dart';
export 'handler/event_notifier.dart';
export 'router/app_transparent_route.dart';
export 'router/app_route_observer.dart';

// 3rd party
export 'package:auto_route/auto_route.dart';
export 'package:flutter/material.dart';
export 'package:get_it/get_it.dart';
export 'package:injectable/injectable.dart';
export 'package:signals_flutter/signals_flutter.dart';
export 'package:equatable/equatable.dart';
```

`apps/mobile/lib/core/dependency/dependency.dart` (replace the whole file; adds `throwOnMissingDependencies`):

```dart
import 'dart:async';
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'package:shellx_mobile/core/dependency/dependency.config.dart';

final getIt = GetIt.instance;

@InjectableInit(
  initializerName: 'init',
  preferRelativeImports: true,
  asExtension: true,
  // A missing registration fails `build_runner` instead of crashing at launch.
  throwOnMissingDependencies: true,
)
FutureOr<GetIt> configureDependencies({String? environment}) {
  return getIt.init(environment: environment);
}

Future<void> resetDependencies({String? environment}) async {
  await getIt.reset();
  configureDependencies(environment: environment);
}
```

`apps/mobile/lib/core/dependency/module.dart` (replace the whole file; the secure-storage, auth-handler and user-handler registrations go, Task 3 adds the ShellX ones):

```dart
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shellx_mobile/core/router/app_router.dart';

@module
abstract class Module {
  @lazySingleton
  @preResolve
  Future<SharedPreferences> get sharedPref => SharedPreferences.getInstance();

  @injectable
  BuildContext context(AppRouter appRouter) {
    final context = appRouter.navigatorKey.currentContext!;
    return context;
  }
}
```

`apps/mobile/lib/core/architecture/error_factory.dart` (replace the whole file; no `dio`, and the title is a localized text — Task 9 maps the ShellX errors):

```dart
import 'package:shellx_mobile/core/architecture/error.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Turns anything a guarded call throws into the [AppError] the user sees.
///
/// The title is always a localized text, never the thrown object's `toString()`: API and relay
/// failures can carry request details (overview §2).
class ErrorFactory {
  AppError fromException(Object e, {StackTrace? stackTrace}) {
    return UnknownError(
      title: S.current.somethingWentWrongPleaseTryAgain,
      stackTrace: stackTrace,
      originalError: e,
    );
  }
}
```

`apps/mobile/lib/core/architecture/controller.dart` (replace the whole file; the guard now maps through `errorFactory`, toasts `error.title` instead of `error.toString()`, and logs only the error type in debug builds):

```dart
import 'package:flutter/foundation.dart';
import 'package:shellx_mobile/core/core.dart';

abstract class Controller {
  PopupHandler get popupHandler {
    _popupHandler ??= getIt<PopupHandler>();
    return _popupHandler!;
  }

  PopupHandler? _popupHandler;

  ErrorFactory get errorFactory {
    _errorFactory ??= ErrorFactory();
    return _errorFactory!;
  }

  ErrorFactory? _errorFactory;

  Future<void> mainStateGuard<T extends Equatable>(
    Future<T> Function() func, {
    required StateSignal<T> state,
    bool showError = false,
    String Function(AppError)? computeErrorMessage,
  }) async {
    try {
      state.loading();
      await batch(() async {
        final result = await func();
        state.complete(result);
      });
    } catch (e, stackTrace) {
      final error = _mapToAppError(e, stackTrace);
      _handleError(
        error,
        showError: showError,
        computeErrorMessage: computeErrorMessage,
      );
      state.failure(error);
    }
  }

  Future guard(
    Future Function() func, {
    bool showError = true,
    String Function(AppError)? computeErrorMessage,
  }) async {
    try {
      await func();
    } catch (e, stackTrace) {
      final error = _mapToAppError(e, stackTrace);
      _handleError(
        error,
        showError: showError,
        computeErrorMessage: computeErrorMessage,
      );
    }
  }

  void _handleError(
    AppError error, {
    required bool showError,
    String Function(AppError)? computeErrorMessage,
  }) {
    // Only the type: an API or relay failure may carry request details, and payloads, tokens and
    // passwords are never logged (overview §2).
    if (kDebugMode) debugPrint('Guard error: ${(error.originalError ?? error).runtimeType}');
    if (!showError) return;
    popupHandler.showError(
      title: computeErrorMessage?.call(error) ?? error.title,
      description: error.description,
    );
  }

  AppError _mapToAppError(Object e, StackTrace stackTrace) {
    if (e is AppError) return e;
    return errorFactory.fromException(e, stackTrace: stackTrace);
  }
}
```

`apps/mobile/lib/core/router/app_route_observer.dart` (replace the whole file; `print` → `debugPrint` in debug builds only):

```dart
import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppRouteObserver extends AutoRouterObserver {
  @override
  void didPush(Route route, Route? previousRoute) {
    if (kDebugMode) debugPrint('Router pushed: ${route.settings.name}');
  }

  // only override to observer tab routes
  @override
  void didInitTabRoute(TabPageRoute route, TabPageRoute? previousRoute) {
    if (kDebugMode) debugPrint('Router visited: ${route.name}');
  }

  @override
  void didChangeTabRoute(TabPageRoute route, TabPageRoute previousRoute) {
    if (kDebugMode) debugPrint('Tab Router re-visited: ${route.name}');
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    if (kDebugMode) debugPrint('Router didPop: ${route.settings.name}');
  }
}
```

Edit `apps/mobile/lib/core/handler/event_notifier.dart` — replace:

```dart
import 'dart:async';

enum EventPriority {
```

with:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';

enum EventPriority {
```

Edit `apps/mobile/lib/core/handler/event_notifier.dart` — replace:

```dart
      print('EventNotifier notify error: $e');
```

with:

```dart
      // Only the type: the error may carry request details (overview §2).
      if (kDebugMode) debugPrint('EventNotifier notify error: ${e.runtimeType}');
```

Edit `apps/mobile/lib/core/handler/popup_handler.dart` — replace:

```dart
import 'dart:developer';
```

with:

```dart
import 'package:flutter/foundation.dart';
```

Edit `apps/mobile/lib/core/handler/popup_handler.dart` — replace:

```dart
      log('DEBUG PopupHandler hide error: $e');
```

with:

```dart
      if (kDebugMode) debugPrint('PopupHandler hide error: ${e.runtimeType}');
```

`apps/mobile/lib/core/router/app_router.dart` (replace the whole file; one placeholder route until Task 19):

```dart
import 'package:auto_route/auto_route.dart';
import 'package:injectable/injectable.dart';
import 'package:shellx_mobile/core/router/app_router.gr.dart';

@singleton
@AutoRouterConfig(replaceInRouteName: 'Screen|Page,Route')
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    // Placeholder home; Task 19 replaces it with the ShellX routes and their guards.
    AutoRoute(page: StartRoute.page, initial: true),
  ];
}
```

`apps/mobile/lib/features/app/start_page.dart`:

```dart
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Placeholder home of the scaffold. Task 19 deletes it when the ShellX routes arrive.
@RoutePage()
class StartPage extends StatelessWidget {
  const StartPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(S.of(context).appTitle, style: context.typo.heading28.bold),
      ),
    );
  }
}
```

Edit `apps/mobile/lib/features/app/app.dart` — replace:

```dart
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/core/router/app_route_observer.dart';
```

with:

```dart
import 'package:shellx_mobile/core/core.dart';
```

Edit `apps/mobile/lib/features/app/app.dart` — replace:

```dart
        child: MaterialApp.router(
          showSemanticsDebugger: false,
```

with:

```dart
        child: MaterialApp.router(
          onGenerateTitle: (context) => S.of(context).appTitle,
          showSemanticsDebugger: false,
```

Flutter 3.41 reports `use_null_aware_elements` twice in the base. Edit `apps/mobile/lib/shared/src/app_button.dart` — replace:

```dart
                    if (prefix != null) prefix!,
```

with:

```dart
                    ?prefix,
```

Edit `apps/mobile/lib/shared/src/app_button.dart` — replace:

```dart
                    if (suffix != null) suffix!,
```

with:

```dart
                    ?suffix,
```

- [ ] **Step 10: Generate, analyze and run the tests**

```bash
cd apps/mobile
dart run intl_utils:generate
dart run build_runner build
flutter analyze
flutter test
```

Expected: `intl_utils` writes `lib/shared/src/l10n.dart` and `lib/shared/src/intl/messages_{all,en,vi}.dart`; `build_runner` rewrites `dependency.config.dart`, `app_router.gr.dart` (`SplashRoute` and `StartRoute`), `assets.gen.dart` and `fonts.gen.dart` (now with `FontFamily.jetBrainsMono`); `No issues found!`; `+141: All tests passed!` (the 14 new tests and the base's validator tests).

- [ ] **Step 11: CI — fail when generated code is stale**

Edit `.github/workflows/ci.yml` — replace:

```yaml
      - run: flutter pub get
      - run: flutter test
```

with:

```yaml
      - run: flutter pub get
      - name: Generated code is up to date
        run: |
          dart run intl_utils:generate
          dart run build_runner build
          git diff --exit-code -- .
          untracked="$(git ls-files --others --exclude-standard -- .)"
          if [ -n "$untracked" ]; then
            echo "::error::Generated files are not committed:"
            echo "$untracked"
            exit 1
          fi
      - run: flutter test
```

(That pair of lines only occurs in the `mobile` job, whose `working-directory` is `apps/mobile`.) Check the freshness step locally after committing (Step 12): `cd apps/mobile && dart run intl_utils:generate && dart run build_runner build && git diff --exit-code -- . && git ls-files --others --exclude-standard -- .` → no output, exit code 0.

- [ ] **Step 12: Commit**

```bash
git add pubspec.yaml .github/workflows/ci.yml apps/mobile
git commit -m "feat(mobile): scaffold apps/mobile from the yallabb base"
```

---

### Task 2: Design tokens and shared widgets from the approved design

The design file is binding here: the light `--a-*` variables become the base's `LightColors`, the dark `--a-*` variables replace the base's placeholder `DarkColors`, the `--t-*` variables become `TerminalColors` (an xterm `TerminalTheme`, dark in both app themes), and the UI font keeps the base's Raleway with lining numerals (the design sets `font-variant-numeric: lining-nums`). Buttons are 54 pt high with radius 15 (design `.btn`), fields radius 13 (design `.field`).

**Files:**
- Modify: `apps/mobile/lib/core/design/app_colors.dart`, `light_colors.dart`, `dark_colors.dart`, `typography.dart`, `theme_data_factory.dart`
- Create: `apps/mobile/lib/core/design/terminal_colors.dart`
- Modify: `apps/mobile/lib/core/core.dart` (exports `terminal_colors.dart`)
- Modify: `apps/mobile/lib/shared/src/app_button.dart`, `apps/mobile/lib/shared/src/app_text_field.dart`, `apps/mobile/lib/features/auth/presentation/widgets/password_text_field.dart`, `apps/mobile/lib/shared/shared.dart`
- Create: `apps/mobile/lib/shared/src/shellx_logo.dart`, `status_circle.dart`, `notice_banner.dart`, `highlighted_text.dart`, `confirm_dialog.dart`
- Test: `apps/mobile/test/core/design/design_tokens_test.dart`

**Interfaces:**
- Produces (colours, all on `context.colors`): the base's `primary`, `background`, `surface`, `primaryText`, `secondaryText`, `disable`, `border`, `divider`, `error` with the design's values, plus `onPrimary`, `primarySoft`, `ok`, `okDot`, `warn`, `warnSoft`, `errorSoft`, `scrim`, `keyboardBackground`, `keyboardKey`, `keyboardInk`.
- Produces: `TerminalColors.{background, chrome, chrome2, line, foreground, dim, title, green, cyan, yellow, red, blue, magenta, secondaryAction, onCyan, noticeBackground, noticeText, noticeBorder}` and `TerminalColors.theme` (`TerminalTheme`); `AppTypography.liningFigures`.
- Produces widgets: `AppButton({title, onTap, state, radius = 15, textColor, …})` (54 pt; `ButtonState.disable` dims to 45 %), `AppTextField({…, errorText, helperText, autofillHints})`, `appInputDecoration(context, {…})`, `PasswordTextField({label, hintText, controller, validator, onChanged, onFieldSubmitted, errorText, helperText, autofillHints, textInputAction})`, `ShellxLogo({size = 64})`, `StatusCircle({icon, tone})` with `StatusTone {ok, error, warn}`, `NoticeBanner({text, tone, leading, action})` with `NoticeTone {warn, info}` and `NoticeSpinner`, `HighlightedText({text, parts, style, partStyle, textAlign})` (tappable `parts`), `showConfirmDialog(context, {message, confirmLabel}) → Future<bool>`.

- [ ] **Step 1: Write the failing test**

`apps/mobile/test/core/design/design_tokens_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/shared/shared.dart';

import '../../support/app_harness.dart';

/// Values copied from `docs/superpowers/design/2026-09-25-shellx-mobile-ui.html`.
void main() {
  test('light palette = the design\'s light --a-* tokens', () {
    final c = Brightness.light.appColors;
    expect(c.background, const Color(0xFFF2F7F8));
    expect(c.surface, const Color(0xFFFFFFFF));
    expect(c.primaryText, const Color(0xFF111111));
    expect(c.secondaryText, const Color(0xFF434B56));
    expect(c.disable, const Color(0xFF8B8F95));
    expect(c.border, const Color(0xFFD8D9DB));
    expect(c.divider, const Color(0xFFEBECED));
    expect(c.primary, const Color(0xFF0097A8));
    expect(c.onPrimary, const Color(0xFFFFFFFF));
    expect(c.primarySoft, const Color(0xFFDCF1F3));
    expect(c.ok, const Color(0xFF3E8A2B));
    expect(c.okDot, const Color(0xFF4CAF3A));
    expect(c.warn, const Color(0xFF9A5600));
    expect(c.warnSoft, const Color(0xFFFCF2E5));
    expect(c.error, const Color(0xFFCB232B));
    expect(c.errorSoft, const Color(0xFFFAE9EA));
    expect(c.keyboardBackground, const Color(0xFFD1D4DA));
  });

  test('dark palette = the design\'s dark --a-* tokens (not the base placeholder)', () {
    final c = Brightness.dark.appColors;
    expect(c.background, const Color(0xFF0D1315));
    expect(c.surface, const Color(0xFF172023));
    expect(c.primaryText, const Color(0xFFE8EFF1));
    expect(c.secondaryText, const Color(0xFFA7B6BA));
    expect(c.disable, const Color(0xFF6F8186));
    expect(c.border, const Color(0xFF2B373A));
    expect(c.divider, const Color(0xFF1F292C));
    expect(c.primary, const Color(0xFF2DBFCF));
    expect(c.onPrimary, const Color(0xFF04282D));
    expect(c.primarySoft, const Color(0xFF0E363C));
    expect(c.okDot, const Color(0xFF6BCB4E));
    expect(c.warn, const Color(0xFFF0A94A));
    expect(c.error, const Color(0xFFF26A70));
    expect(c.errorSoft, const Color(0xFF3B1719));
    expect(c.keyboardKey, const Color(0xFF47484B));
  });

  test('the terminal is dark in both themes (--t-*)', () {
    expect(TerminalColors.theme.background, const Color(0xFF0B1215));
    expect(TerminalColors.theme.foreground, const Color(0xFFD4E1E4));
    expect(TerminalColors.theme.green, const Color(0xFF7ED492));
    expect(TerminalColors.theme.cyan, const Color(0xFF5FD4E2));
    expect(TerminalColors.chrome, const Color(0xFF111B1E));
  });

  test('UI text uses lining numerals; Material widgets take the ShellX primary', () {
    expect(AppTypography.instance.paragraph.fontFeatures, AppTypography.liningFigures);
    expect(AppTypography.instance.display32.fontFeatures, AppTypography.liningFigures);
    final theme = ThemeDataFactory.create(Brightness.dark);
    expect(theme.colorScheme.primary, const Color(0xFF2DBFCF));
    expect(theme.scaffoldBackgroundColor, const Color(0xFF0D1315));
  });

  testWidgets('buttons: 54 pt, radius 15; disabled keeps its colours at 45 % opacity', (tester) async {
    await tester.pumpWidget(
      localized(
        const Scaffold(
          body: Column(
            children: [
              AppButton(title: 'on'),
              AppButton(title: 'off', state: ButtonState.disable),
            ],
          ),
        ),
      ),
    );
    expect(tester.getSize(find.widgetWithText(AppButton, 'on')).height, 54);
    final ink = tester.widget<Ink>(find.descendant(of: find.widgetWithText(AppButton, 'on'), matching: find.byType(Ink)));
    expect((ink.decoration! as BoxDecoration).borderRadius, BorderRadius.circular(15));
    final dimmed = tester.widget<Opacity>(
      find.descendant(of: find.widgetWithText(AppButton, 'off'), matching: find.byType(Opacity)).first,
    );
    expect(dimmed.opacity, 0.45);
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd apps/mobile && flutter test test/core/design/design_tokens_test.dart`
Expected: FAIL — compilation errors (`onPrimary`, `TerminalColors`, `AppTypography.liningFigures` are not defined).

- [ ] **Step 3: Colours, terminal theme, typography, Material theme**

`apps/mobile/lib/core/design/app_colors.dart` (replace the whole file):

```dart
import 'package:flutter/material.dart';
import 'package:shellx_mobile/core/design/dark_colors.dart';
import 'light_colors.dart';

abstract class AppColors {
  Color get primary;
  Color get accent;
  Color get primaryText;
  Color get secondaryText;
  Color get disable;
  Color get border;
  Color get divider;
  Color get background;
  Color get surface;
  Color get white;
  Color get black;
  Color get error;
  Color get mainRed;
  Color get mediumRed;
  Color get lightRed;
  Color get mainGold;
  Color get lightGold;
  Color get mainGreen;
  Color get lightGreen;
  Color get mediumOrange;
  Color get blueGrey;
  Gradient get gradient;
  double get opacity => 0.12;

  // ShellX design (docs/superpowers/design/2026-09-25-shellx-mobile-ui.html, `--a-*` tokens).
  /// Text and icons on [primary].
  Color get onPrimary;

  /// Tinted background of soft buttons, badges and icon tiles.
  Color get primarySoft;

  /// "Online" text.
  Color get ok;

  /// The online dot.
  Color get okDot;

  /// Warning text (lost-connection banner).
  Color get warn;

  /// Warning background.
  Color get warnSoft;

  /// Error background (delete-account warning box, error icons).
  Color get errorSoft;

  /// Dimming behind sheets and dialogs.
  Color get scrim;

  /// Extra keys bar (`--kb-*`): it follows the system keyboard's light or dark look.
  Color get keyboardBackground;
  Color get keyboardKey;
  Color get keyboardInk;

  void setPrimaryColor(Color color);

  void setAccentColor(Color color);

  void setBackgroundColor(Color color);
}

extension BrightnessTheme on Brightness {
  AppColors get appColors {
    return this == Brightness.light ? LightColors() : DarkColors();
  }
}
```

`apps/mobile/lib/core/design/light_colors.dart` (replace the whole file):

```dart
import 'package:flutter/material.dart';
import 'app_colors.dart';

class LightColors extends AppColors {
  @override
  Color primary = const Color(0xff0097A8);

  @override
  Color accent = const Color(0xFF7AAB3C);

  @override
  Color primaryText = const Color(0xFF111111);

  @override
  Color secondaryText = const Color(0xFF434B56);

  @override
  Color disable = const Color(0xFF8B8F95);

  @override
  Color border = const Color(0xFFD8D9DB);

  @override
  Color divider = const Color(0xFFEBECED);

  @override
  Color background = const Color(0xffF2F7F8);

  @override
  Color white = const Color(0xFFFFFFFF);

  @override
  Color surface = const Color(0xFFFFFFFF);

  @override
  Color error = const Color(0xFFCB232B);

  @override
  Color mainRed = const Color(0xFFCB232B);

  @override
  Color lightRed = const Color(0xFFFAE9EA);

  @override
  Color mainGold = const Color(0xFFE17E00);

  @override
  Color lightGold = const Color(0xFFFCF2E5);

  @override
  Color mainGreen = const Color(0xFF5A9B3D);

  @override
  Color lightGreen = const Color(0xFFEEF5EC);

  @override
  Gradient gradient = const LinearGradient(
    colors: [Color(0xFFDD801A), Color(0xFFDE3915)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  @override
  Color mediumRed = const Color(0xFFDE3915);

  @override
  Color mediumOrange = const Color(0xFFDD801A);

  @override
  Color black = Colors.black;

  @override
  Color blueGrey = const Color.fromARGB(255, 6, 35, 47);

  // ShellX design, light `--a-*` tokens.
  @override
  Color get onPrimary => const Color(0xFFFFFFFF);

  @override
  Color get primarySoft => const Color(0xFFDCF1F3);

  @override
  Color get ok => const Color(0xFF3E8A2B);

  @override
  Color get okDot => const Color(0xFF4CAF3A);

  @override
  Color get warn => const Color(0xFF9A5600);

  @override
  Color get warnSoft => const Color(0xFFFCF2E5);

  @override
  Color get errorSoft => const Color(0xFFFAE9EA);

  @override
  Color get scrim => const Color(0x730A1418);

  @override
  Color get keyboardBackground => const Color(0xFFD1D4DA);

  @override
  Color get keyboardKey => const Color(0xFFFFFFFF);

  @override
  Color get keyboardInk => const Color(0xFF000000);

  @override
  void setAccentColor(Color color) {
    accent = color;
  }

  @override
  void setBackgroundColor(Color color) {
    background = color;
  }

  @override
  void setPrimaryColor(Color color) {
    primary = color;
  }
}
```

`apps/mobile/lib/core/design/dark_colors.dart` (replace the whole file — the base's placeholder dark palette is gone):

```dart
import 'package:flutter/material.dart';
import 'package:shellx_mobile/core/design/light_colors.dart';

/// Dark `--a-*` tokens of the ShellX design (the base only had a placeholder here).
class DarkColors extends LightColors {
  DarkColors() {
    // `primary` and `background` are fields of LightColors (they have setters).
    primary = const Color(0xFF2DBFCF);
    background = const Color(0xFF0D1315);
  }

  @override
  Color get primaryText => const Color(0xFFE8EFF1);

  @override
  Color get secondaryText => const Color(0xFFA7B6BA);

  @override
  Color get disable => const Color(0xFF6F8186);

  @override
  Color get border => const Color(0xFF2B373A);

  @override
  Color get divider => const Color(0xFF1F292C);

  @override
  Color get surface => const Color(0xFF172023);

  @override
  Color get error => const Color(0xFFF26A70);

  @override
  Color get mainRed => const Color(0xFFF26A70);

  @override
  Color get lightRed => const Color(0xFF3B1719);

  @override
  Color get mainGreen => const Color(0xFF7CC45E);

  @override
  Color get lightGold => const Color(0xFF33250F);

  @override
  Color get black => Colors.black;

  @override
  Color get onPrimary => const Color(0xFF04282D);

  @override
  Color get primarySoft => const Color(0xFF0E363C);

  @override
  Color get ok => const Color(0xFF7CC45E);

  @override
  Color get okDot => const Color(0xFF6BCB4E);

  @override
  Color get warn => const Color(0xFFF0A94A);

  @override
  Color get warnSoft => const Color(0xFF33250F);

  @override
  Color get errorSoft => const Color(0xFF3B1719);

  @override
  Color get scrim => const Color(0x99000000);

  @override
  Color get keyboardBackground => const Color(0xFF1E1F21);

  @override
  Color get keyboardKey => const Color(0xFF47484B);

  @override
  Color get keyboardInk => const Color(0xFFFFFFFF);
}
```

`apps/mobile/lib/core/design/terminal_colors.dart`:

```dart
import 'package:flutter/painting.dart';
import 'package:xterm/xterm.dart';

/// Terminal colours of the ShellX design (`--t-*`): the terminal is dark in both app themes.
abstract final class TerminalColors {
  static const Color background = Color(0xFF0B1215);
  static const Color chrome = Color(0xFF111B1E);
  static const Color chrome2 = Color(0xFF1A272B);
  static const Color line = Color(0xFF243337);
  static const Color foreground = Color(0xFFD4E1E4);
  static const Color dim = Color(0xFF6C8288);
  static const Color title = Color(0xFFE8F0F2);
  static const Color green = Color(0xFF7ED492);
  static const Color cyan = Color(0xFF5FD4E2);
  static const Color yellow = Color(0xFFE9C46A);
  static const Color red = Color(0xFFF07178);
  static const Color blue = Color(0xFF82AAFF);
  static const Color magenta = Color(0xFFC792EA);

  /// "Đóng tab" on the session-ended card.
  static const Color secondaryAction = Color(0xFF23353A);

  /// Text on a cyan button.
  static const Color onCyan = Color(0xFF05282D);

  /// Floating notice (e.g. `session_limit`).
  static const Color noticeBackground = Color(0xFF2A1416);
  static const Color noticeText = Color(0xFFFFD9DB);
  static const Color noticeBorder = Color(0xFF5A2A2E);

  /// ANSI palette for xterm.
  static const TerminalTheme theme = TerminalTheme(
    cursor: foreground,
    selection: Color(0x665FD4E2),
    foreground: foreground,
    background: background,
    black: chrome2,
    red: red,
    green: green,
    yellow: yellow,
    blue: blue,
    magenta: magenta,
    cyan: cyan,
    white: foreground,
    brightBlack: dim,
    brightRed: Color(0xFFFF8F95),
    brightGreen: Color(0xFF9BE3AB),
    brightYellow: Color(0xFFF2D68C),
    brightBlue: Color(0xFFA5C2FF),
    brightMagenta: Color(0xFFDAB3F1),
    brightCyan: Color(0xFF8FE3EC),
    brightWhite: Color(0xFFFFFFFF),
    searchHitBackground: yellow,
    searchHitBackgroundCurrent: cyan,
    searchHitForeground: background,
  );
}
```

`apps/mobile/lib/core/design/typography.dart` (replace the whole file; every style gets `fontFeatures: liningFigures`):

```dart
import 'package:flutter/material.dart';

class AppTypography {
  final FontWeight fontWeight = FontWeight.w400;
  Color color = Colors.black;

  /// ShellX design: Raleway with lining numerals, so times and versions sit on the line.
  static const List<FontFeature> liningFigures = [FontFeature.liningFigures()];

  TextStyle get display56 => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 56,
    fontWeight: fontWeight,
    height: 1.4,
    color: color,
  );

  //42
  TextStyle get display42 => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 42,
    color: color,
    height: 1.5,
    fontWeight: fontWeight,
  );

  //36
  TextStyle get display36 => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 36,
    color: color,
    height: 1.5,
    fontWeight: fontWeight,
  );
  //32
  TextStyle get display32 => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 32,
    color: color,
    height: 1.5,
    fontWeight: fontWeight,
  );

  //28
  TextStyle get heading28 => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 28,
    color: color,
    height: 1.5,
    fontWeight: fontWeight,
  );

  //28
  TextStyle get heading26 => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 26,
    color: color,
    height: 1.5,
    fontWeight: fontWeight,
  );

  //24
  TextStyle get heading24 => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 24,
    color: color,
    height: 1.5,
    fontWeight: fontWeight,
  );

  //20
  TextStyle get heading20 => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 20,
    color: color,
    height: 1.6,
    fontWeight: fontWeight,
  );

  //18
  TextStyle get title => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 18,
    color: color,
    height: 1.61,
    fontWeight: fontWeight,
  );

  //16
  TextStyle get subHeader => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 16,
    color: color,
    height: 1.625,
    fontWeight: fontWeight,
  );
  //16
  TextStyle get subHeader15 => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 15,
    color: color,
    height: 1.625,
    fontWeight: fontWeight,
  );

  //14
  TextStyle get paragraph => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 14,
    color: color,
    height: 1.57,
    fontWeight: fontWeight,
  );

  TextStyle get paragraph13 => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 13,
    color: color,
    height: 1.57,
    fontWeight: fontWeight,
  );

  //12
  TextStyle get metadata12 => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 12,
    color: color,
    height: 19 / 12,
    fontWeight: fontWeight,
  );

  //12
  TextStyle get metadata11 => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 11,
    color: color,
    height: 19 / 12,
    fontWeight: fontWeight,
  );

  //10
  TextStyle get metadata10 => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 10,
    color: color,
    height: 1.6,
    fontWeight: fontWeight,
  );

  //10
  TextStyle get metadata8 => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 8,
    color: color,
    height: 1.6,
    fontWeight: fontWeight,
  );

  AppTypography._internal();

  static AppTypography instance = _instance;

  static final AppTypography _instance = AppTypography._internal();

  void setColor(Color color) {
    this.color = color;
  }
}

extension ColorTextStyle on TextStyle {
  TextStyle mergeColor(Color color) {
    return copyWith(color: color);
  }

  TextStyle get heavy {
    return copyWith(fontWeight: FontWeight.w800);
  }

  TextStyle get semiBold {
    return copyWith(fontWeight: FontWeight.w600);
  }

  TextStyle get bold {
    return copyWith(fontWeight: FontWeight.w700);
  }

  TextStyle get medium {
    return copyWith(fontWeight: FontWeight.w500);
  }

  TextStyle get underline {
    return copyWith(
      decoration: TextDecoration.underline,
      decorationColor: color,
    );
  }

  TextStyle get italic {
    return copyWith(fontStyle: FontStyle.italic);
  }

  TextStyle get white => copyWith(color: Colors.white, decorationColor: Colors.white);
}
```

`apps/mobile/lib/core/design/theme_data_factory.dart` (replace the whole file):

```dart
import 'package:universal_back_gesture/universal_back_gesture.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/shared/shared.dart';

class ThemeDataFactory {
  static ThemeData create(Brightness brightness) {
    final appColors = brightness.appColors;
    // Material widgets (switches, sliders, text buttons) take the ShellX tokens, not the M3 seed.
    final colorScheme = ColorScheme.fromSeed(seedColor: appColors.primary, brightness: brightness).copyWith(
      primary: appColors.primary,
      onPrimary: appColors.onPrimary,
      primaryContainer: appColors.primarySoft,
      surface: appColors.surface,
      onSurface: appColors.primaryText,
      onSurfaceVariant: appColors.secondaryText,
      error: appColors.error,
      outline: appColors.border,
      outlineVariant: appColors.divider,
    );
    return ThemeData(
      colorScheme: colorScheme,
      primaryColor: appColors.primary,
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final platform in TargetPlatform.values)
            platform: BackGesturePageTransitionsBuilder(
              parentTransitionBuilder: const CupertinoPageTransitionsBuilder(),
              config: BackGestureConfig(
                swipeTransitionRange: const GestureMeasurement.percentage(1.0),
                commitAnimationDuration: Duration(milliseconds: 100),
                commitAnimationCurve: Curves.easeOutQuart,
                animationProgressCompleteThreshold: 0.4,
              ),
            ),
        },
      ),
      iconTheme: IconThemeData(
        color: appColors.primary,
      ),
      brightness: brightness,
      useMaterial3: true,
      fontFamily: FontFamily.raleway,
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: appColors.primary,
      ),
      scaffoldBackgroundColor: appColors.background,
      dividerColor: appColors.divider,
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: appColors.white,
        selectedItemColor: appColors.primaryText,
        unselectedItemColor: appColors.secondaryText,
        showUnselectedLabels: true,
        showSelectedLabels: true,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: appColors.background,
        foregroundColor: appColors.primary,
        surfaceTintColor: appColors.background,
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: appColors.primaryText,
          fontFamily: FontFamily.raleway,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          fontFeatures: AppTypography.liningFigures,
        ),
        iconTheme: IconThemeData(
          color: appColors.primary,
        ),
      ),
    );
  }
}
```

`apps/mobile/lib/core/core.dart` (replace the whole file):

```dart
export 'dependency/dependency.dart';
export 'design/app_colors.dart';
export 'design/dark_colors.dart';
export 'design/light_colors.dart';
export 'design/typography.dart';
export 'design/design_system.dart';
export 'design/theme_data_factory.dart';
export 'design/terminal_colors.dart';
export 'extensions/adaptive_theme_mode_x.dart';
export 'router/app_router.dart';
export 'architecture/error.dart';
export 'architecture/error_factory.dart';
export 'architecture/controller.dart';
export 'architecture/state_signal.dart';
export 'handler/popup_handler.dart';
export 'architecture/page_domain.dart';
export 'architecture/paging_state_signal.dart';
export 'architecture/state.dart';
export 'router/app_router.gr.dart';
export 'handler/event_notifier.dart';
export 'router/app_transparent_route.dart';
export 'router/app_route_observer.dart';

// 3rd party
export 'package:auto_route/auto_route.dart';
export 'package:flutter/material.dart';
export 'package:get_it/get_it.dart';
export 'package:injectable/injectable.dart';
export 'package:signals_flutter/signals_flutter.dart';
export 'package:equatable/equatable.dart';
```

- [ ] **Step 4: Shared widgets in the design's style**

`apps/mobile/lib/shared/src/app_button.dart` (replace the whole file):

```dart
import 'package:shellx_mobile/core/core.dart';

enum ButtonState {
  available,
  disable,
  loading
  ;

  bool get isAvailable => this == available;
  bool get isDisable => this == disable;
  bool get isLoading => this == loading;
}

/// ShellX design `.btn`: 54 pt tall, radius 15, bold label on [AppColors.primary]; a disabled
/// button keeps its colours at 45 % opacity ("nút mờ tới khi hợp lệ").
class AppButton extends StatelessWidget {
  final double height;
  final double? width;
  final ButtonState state;
  final Function()? onTap;
  final String title;
  final Widget? suffix;
  final Widget? prefix;
  final EdgeInsets? padding;
  final Color? backgroundColor;
  final Color? textColor;
  final Border? border;
  final TextStyle? textStyle;
  final MainAxisSize? mainAxisSize;
  final double radius;

  const AppButton({
    super.key,
    this.height = 54,
    this.width,
    this.state = ButtonState.available,
    this.onTap,
    required this.title,
    this.suffix,
    this.prefix,
    this.padding,
    this.backgroundColor,
    this.border,
    this.textColor,
    this.textStyle,
    this.mainAxisSize,
    this.radius = 15,
  });

  @override
  Widget build(BuildContext context) {
    final background = backgroundColor ?? context.colors.primary;
    final foreground = textColor ?? context.colors.onPrimary;
    final shape = BorderRadius.circular(radius);
    return Opacity(
      opacity: state.isDisable ? 0.45 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: state.isAvailable ? onTap : null,
          borderRadius: shape,
          child: Ink(
            height: height,
            width: width,
            padding: padding ?? const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: border,
              color: background,
              borderRadius: shape,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: state.isLoading ? 0 : 1,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: mainAxisSize ?? MainAxisSize.min,
                    children: [
                      ?prefix,
                      Flexible(
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: context.typo.subHeader.bold.copyWith(color: foreground).merge(textStyle),
                        ),
                      ),
                      ?suffix,
                    ],
                  ),
                ),
                if (state.isLoading)
                  SizedBox.square(
                    dimension: height / 2.4,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: foreground),
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

`apps/mobile/lib/shared/src/app_text_field.dart` (replace the whole file):

```dart
import 'package:shellx_mobile/core/core.dart';

/// ShellX design `.field`: bold label, 52 pt input with radius 13; [errorText] (e.g. an answer
/// from the relay) and [helperText] sit right under the field.
class AppTextField extends StatefulWidget {
  final String label;
  final String? hintText;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool enabled;
  final int? maxLines;
  final TextInputAction? textInputAction;
  final void Function(String)? onChanged;
  final void Function(String)? onFieldSubmitted;
  final String? errorText;
  final String? helperText;
  final Iterable<String>? autofillHints;

  const AppTextField({
    super.key,
    required this.label,
    this.hintText,
    this.controller,
    this.validator,
    this.keyboardType,
    this.prefixIcon,
    this.suffixIcon,
    this.enabled = true,
    this.maxLines = 1,
    this.textInputAction,
    this.onChanged,
    this.onFieldSubmitted,
    this.errorText,
    this.helperText,
    this.autofillHints,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late final FocusNode _focusNode;
  bool _hasInteracted = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    // When user unfocuses field, enable validation on change
    if (!_focusNode.hasFocus && !_hasInteracted) {
      setState(() {
        _hasInteracted = true;
      });
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.label,
          style: context.typo.paragraph13.bold.copyWith(color: context.colors.secondaryText),
        ),
        const SizedBox(height: 7),
        TextFormField(
          controller: widget.controller,
          focusNode: _focusNode,
          validator: (value) {
            final error = widget.validator?.call(value);
            // If there's an error and we haven't enabled on-change validation yet, do so
            if (error != null && !_hasInteracted) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _hasInteracted = true;
                  });
                }
              });
            }
            return error;
          },
          keyboardType: widget.keyboardType,
          enabled: widget.enabled,
          maxLines: widget.maxLines,
          textInputAction: widget.textInputAction,
          onChanged: widget.onChanged,
          onFieldSubmitted: widget.onFieldSubmitted,
          autofillHints: widget.autofillHints,
          autovalidateMode: _hasInteracted ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
          style: context.typo.subHeader,
          decoration: appInputDecoration(
            context,
            hintText: widget.hintText,
            prefixIcon: widget.prefixIcon,
            suffixIcon: widget.suffixIcon,
            errorText: widget.errorText,
            helperText: widget.helperText,
          ),
        ),
      ],
    );
  }
}

/// The input box of the ShellX design, shared by [AppTextField] and `PasswordTextField`.
InputDecoration appInputDecoration(
  BuildContext context, {
  String? hintText,
  Widget? prefixIcon,
  Widget? suffixIcon,
  String? errorText,
  String? helperText,
}) {
  final colors = context.colors;
  OutlineInputBorder outline(Color color, double width) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(13),
    borderSide: BorderSide(color: color, width: width),
  );
  return InputDecoration(
    hintText: hintText,
    hintStyle: context.typo.subHeader.copyWith(color: colors.disable),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    errorText: errorText,
    helperText: helperText,
    helperMaxLines: 3,
    errorMaxLines: 3,
    helperStyle: context.typo.paragraph13.copyWith(color: colors.secondaryText),
    filled: true,
    fillColor: colors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    border: outline(colors.border, 1.5),
    enabledBorder: outline(colors.border, 1.5),
    focusedBorder: outline(colors.primary, 2),
    errorBorder: outline(colors.error, 1.5),
    focusedErrorBorder: outline(colors.error, 2),
    disabledBorder: outline(colors.border.withValues(alpha: 0.5), 1.5),
    errorStyle: context.typo.paragraph13.bold.copyWith(color: colors.error),
  );
}
```

`apps/mobile/lib/features/auth/presentation/widgets/password_text_field.dart` (replace the whole file; the base widget with inline error/helper text, autofill hints and the design's eye toggle):

```dart
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Password field with the eye button (the ShellX design has no "repeat password" field).
class PasswordTextField extends StatefulWidget {
  final String label;
  final String? hintText;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;
  final void Function(String)? onChanged;
  final void Function(String)? onFieldSubmitted;
  final String? errorText;
  final String? helperText;
  final Iterable<String>? autofillHints;

  const PasswordTextField({
    super.key,
    required this.label,
    this.hintText,
    this.controller,
    this.validator,
    this.textInputAction,
    this.onChanged,
    this.onFieldSubmitted,
    this.errorText,
    this.helperText,
    this.autofillHints,
  });

  @override
  State<PasswordTextField> createState() => _PasswordTextFieldState();
}

class _PasswordTextFieldState extends State<PasswordTextField> {
  bool _obscureText = true;
  late final FocusNode _focusNode;
  bool _hasInteracted = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    // When user unfocuses field, enable validation on change
    if (!_focusNode.hasFocus && !_hasInteracted) {
      setState(() {
        _hasInteracted = true;
      });
    }
  }

  void _toggleVisibility() {
    setState(() {
      _obscureText = !_obscureText;
    });
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.label,
          style: context.typo.paragraph13.bold.copyWith(color: context.colors.secondaryText),
        ),
        const SizedBox(height: 7),
        TextFormField(
          controller: widget.controller,
          focusNode: _focusNode,
          validator: (value) {
            final error = widget.validator?.call(value);
            // If there's an error and we haven't enabled on-change validation yet, do so
            if (error != null && !_hasInteracted) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _hasInteracted = true;
                  });
                }
              });
            }
            return error;
          },
          obscureText: _obscureText,
          textInputAction: widget.textInputAction,
          onChanged: widget.onChanged,
          onFieldSubmitted: widget.onFieldSubmitted,
          autofillHints: widget.autofillHints,
          autovalidateMode: _hasInteracted ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
          style: context.typo.subHeader,
          decoration: appInputDecoration(
            context,
            hintText: widget.hintText,
            errorText: widget.errorText,
            helperText: widget.helperText,
            suffixIcon: IconButton(
              icon: Icon(
                _obscureText ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: context.colors.disable,
              ),
              onPressed: _toggleVisibility,
            ),
          ),
        ),
      ],
    );
  }
}
```

`apps/mobile/lib/shared/src/shellx_logo.dart`:

```dart
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/shared/src/fonts.gen.dart';

/// The "›_" tile of the ShellX design (`.logo`).
class ShellxLogo extends StatelessWidget {
  const ShellxLogo({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: context.colors.primary, borderRadius: BorderRadius.circular(size * 0.28)),
      child: Text(
        '›_',
        style: TextStyle(
          fontFamily: FontFamily.jetBrainsMono,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.375,
          letterSpacing: -1,
          color: context.colors.onPrimary,
        ),
      ),
    );
  }
}
```

`apps/mobile/lib/shared/src/status_circle.dart`:

```dart
import 'package:shellx_mobile/core/core.dart';

enum StatusTone { ok, error, warn }

/// The round state icon of the ShellX design (`.state-ic`): success, error or warning.
class StatusCircle extends StatelessWidget {
  const StatusCircle({super.key, required this.icon, this.tone = StatusTone.ok});

  final IconData icon;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (background, foreground) = switch (tone) {
      StatusTone.ok => (colors.primarySoft, colors.primary),
      StatusTone.error => (colors.errorSoft, colors.error),
      StatusTone.warn => (colors.warnSoft, colors.warn),
    };
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Icon(icon, size: 38, color: foreground),
    );
  }
}
```

`apps/mobile/lib/shared/src/notice_banner.dart`:

```dart
import 'package:shellx_mobile/core/core.dart';

enum NoticeTone { warn, info }

/// The rounded banner of the ShellX design (`.banner`): the lost-connection notice (warn, with a
/// spinner) and the "sign-in expired" notice on the login page (info, with a lock).
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({super.key, required this.text, this.tone = NoticeTone.warn, this.leading, this.action});

  final String text;
  final NoticeTone tone;
  final Widget? leading;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (background, foreground) = switch (tone) {
      NoticeTone.warn => (colors.warnSoft, colors.warn),
      NoticeTone.info => (colors.primarySoft, colors.primary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(13)),
      child: IconTheme(
        data: IconThemeData(color: foreground, size: 20),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 10)],
            Expanded(
              child: Text(text, style: context.typo.paragraph.bold.copyWith(color: foreground)),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}

/// The small spinner of the lost-connection banner.
class NoticeSpinner extends StatelessWidget {
  const NoticeSpinner({super.key});

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 16,
    child: CircularProgressIndicator(strokeWidth: 2.5, color: IconTheme.of(context).color),
  );
}
```

`apps/mobile/lib/shared/src/highlighted_text.dart`:

```dart
import 'package:shellx_mobile/core/core.dart';

/// [text] with each key of [parts] drawn in [partStyle] — and tappable when its value is not
/// null. Keeps localized sentences whole in the ARB files while the design bolds or links words
/// inside them ("shellx.pro", "Ghép nối điện thoại…", a machine name, "Điều khoản").
class HighlightedText extends StatelessWidget {
  const HighlightedText(
    this.text, {
    super.key,
    required this.parts,
    required this.style,
    required this.partStyle,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final Map<String, VoidCallback?> parts;
  final TextStyle style;
  final TextStyle partStyle;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    var rest = text;
    while (rest.isNotEmpty) {
      // The earliest remaining part wins.
      MapEntry<String, VoidCallback?>? next;
      var at = -1;
      for (final entry in parts.entries) {
        if (entry.key.isEmpty) continue;
        final index = rest.indexOf(entry.key);
        if (index >= 0 && (at < 0 || index < at)) {
          at = index;
          next = entry;
        }
      }
      if (next == null) {
        spans.add(TextSpan(text: rest));
        break;
      }
      if (at > 0) spans.add(TextSpan(text: rest.substring(0, at)));
      final onTap = next.value;
      spans.add(
        onTap == null
            ? TextSpan(text: next.key, style: partStyle)
            : WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: GestureDetector(
                  onTap: onTap,
                  child: Text(next.key, style: style.merge(partStyle)),
                ),
              ),
      );
      rest = rest.substring(at + next.key.length);
    }
    return Text.rich(
      TextSpan(style: style, children: spans),
      textAlign: textAlign,
    );
  }
}
```

`apps/mobile/lib/shared/src/confirm_dialog.dart`:

```dart
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/shared/src/l10n.dart';

/// "Are you sure?" with Cancel and [confirmLabel]; true only when confirmed.
Future<bool> showConfirmDialog(BuildContext context, {required String message, required String confirmLabel}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(message, style: context.typo.subHeader),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(S.of(context).actionCancel)),
        TextButton(onPressed: () => Navigator.pop(context, true), child: Text(confirmLabel)),
      ],
    ),
  );
  return confirmed ?? false;
}
```

`apps/mobile/lib/shared/shared.dart` (replace the whole file):

```dart
export 'src/app_lifecycle_widget.dart';
export 'src/l10n.dart';
export 'src/fonts.gen.dart';
export 'src/assets.gen.dart';
export 'src/app_scroll_view.dart';
export 'src/sliver_bottom_padding.dart';
export 'src/sized_box.dart';
export 'src/app_button.dart';
export 'src/app_circular_progress.dart';
export 'src/item_not_found.dart';
export 'src/sliver_pagination_view.dart';
export 'src/state_view.dart';
export 'src/data_state_view.dart';
export 'src/interface_pagination_view.dart';
export 'src/app_error_view.dart';
export 'src/app_refresh.dart';
export 'src/app_text_field.dart';
export 'src/bottom_bouncing_scroll_physics.dart';
export 'src/confirm_dialog.dart';
export 'src/highlighted_text.dart';
export 'src/notice_banner.dart';
export 'src/shellx_logo.dart';
export 'src/status_circle.dart';
```

- [ ] **Step 5: Run the test, the analyzer and the suite**

```bash
cd apps/mobile
flutter test test/core/design/design_tokens_test.dart
flutter analyze
flutter test
```

Expected: `+5: All tests passed!`; `No issues found!`; `+146: All tests passed!`.

- [ ] **Step 6: Commit**

```bash
git add apps/mobile
git commit -m "feat(mobile): design tokens, terminal theme and shared widgets from the approved design"
```

---

### Task 3: Platform adapters and stores — secure store, fresh-install wipe, device name, links, settings, account storage

**Files:**
- Create: `apps/mobile/lib/core/config/app_config.dart`
- Create: `apps/mobile/lib/core/platform/secure_key_value_store.dart`, `fresh_install.dart`, `device_description.dart`, `external_links.dart`
- Create: `apps/mobile/lib/core/settings/app_settings.dart`
- Create: `apps/mobile/lib/core/auth/account_session.dart`, `apps/mobile/lib/core/auth/auth_storage.dart`
- Modify: `apps/mobile/lib/core/dependency/module.dart`, `apps/mobile/lib/core/core.dart`
- Test: `apps/mobile/test/core/platform/platform_test.dart`, `apps/mobile/test/core/settings/app_settings_test.dart`, `apps/mobile/test/core/auth/auth_storage_test.dart`, `apps/mobile/test/core/dependency_test.dart`

**Interfaces:**
- Consumes: `KeyValueStore`, `DeviceIdentity.storageKey`, `DevicePlatform`, `ShellxApi` (`shellx_core`, overview §5.1/§5.5).
- Produces: `SecureKeyValueStore([FlutterSecureStorage?]) implements KeyValueStore` (+ `deleteAll()`); `wipeSecureStorageOnFreshInstall({prefs, wipe})`, `installMarkerKey`; `DeviceDescription({name, platform})`, `formatAndroidModelName(manufacturer, model)`, `describeThisDevice([DeviceInfoPlugin?])`; `ExternalLinks` (`open(Uri)`, `openAppSettings()`) with `@LazySingleton(as:)` `UrlLauncherLinks`; `AppConfig.{relayBaseUri, downloadPage, appStorePage, playStorePage, termsPage, privacyPage}`, `relayWebSocketUri(Uri)`; `AppSettings` (`@lazySingleton`, loaded before the app starts): `fontSize`/`biometricLock` signals, `setFontSize`, `setBiometricLock`, `clampFontSize`, `defaultFontSize` 14, `minFontSize` 8, `maxFontSize` 32; `AccountSession({userId, deviceId, token, email})`; `AuthStorage` (`load`, `lastEmail`, `save`, `deleteToken`, `forgetAccount(userId)`, key constants) with `@LazySingleton(as:)` `AuthStorageImpl`.
- DI (`Module`): `SharedPreferences`, the one `KeyValueStore` (fresh-install wipe first), `DeviceDescription`, `PackageInfo` (all `@preResolve` lazy singletons) and `ShellxApi(baseUri: AppConfig.relayBaseUri)`.

- [ ] **Step 1: Write the failing tests**

`apps/mobile/test/core/platform/platform_test.dart`:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shellx_mobile/core/config/app_config.dart';
import 'package:shellx_mobile/core/platform/device_description.dart';
import 'package:shellx_mobile/core/platform/fresh_install.dart';
import 'package:shellx_mobile/core/platform/secure_key_value_store.dart';

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
      expect(relayWebSocketUri(Uri.parse('https://relay.shellx.pro')).toString(), 'wss://relay.shellx.pro/v1/ws');
      expect(relayWebSocketUri(Uri.parse('http://127.0.0.1:8787')).toString(), 'ws://127.0.0.1:8787/v1/ws');
    });

    test('defaults to the production relay', () {
      expect(AppConfig.relayBaseUri.toString(), 'https://relay.shellx.pro');
    });
  });
}
```

`apps/mobile/test/core/settings/app_settings_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;

void main() {
  test('defaults: font size 14 and biometric lock on (spec §5.6)', () async {
    final settings = AppSettings(InMemoryKeyValueStore());
    await settings.load();
    expect(settings.fontSize.value, 14);
    expect(settings.biometricLock.value, isTrue);
  });

  test('persists values, clamps the font size to 8..32 and notifies watchers', () async {
    final store = InMemoryKeyValueStore();
    final settings = AppSettings(store);
    final seen = <(double, bool)>[];
    final stop = effect(() => seen.add((settings.fontSize.value, settings.biometricLock.value)));
    addTearDown(stop);

    await settings.setFontSize(99);
    await settings.setBiometricLock(false);

    final reloaded = AppSettings(store);
    await reloaded.load();
    expect(reloaded.fontSize.value, 32);
    expect(reloaded.biometricLock.value, isFalse);
    expect(seen, [(14.0, true), (32.0, true), (32.0, false)]);

    await settings.setFontSize(2);
    expect(settings.fontSize.value, 8);
  });

  test('ignores a corrupt stored font size', () async {
    final store = InMemoryKeyValueStore();
    await store.write(AppSettings.fontSizeKey, 'large');
    final settings = AppSettings(store);
    await settings.load();
    expect(settings.fontSize.value, AppSettings.defaultFontSize);
  });
}
```

`apps/mobile/test/core/auth/auth_storage_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;

void main() {
  const session = AccountSession(userId: 'user-1', deviceId: 'device-1', token: 'token-1', email: 'me@example.com');
  late InMemoryKeyValueStore store;
  late AuthStorage storage;

  setUp(() {
    store = InMemoryKeyValueStore();
    storage = AuthStorageImpl(store);
  });

  test('saves and loads the session under the plan keys', () async {
    expect(await storage.load(), isNull);
    await storage.save(session);
    expect(await storage.load(), session);
    expect(store.values, {
      'auth_token': 'token-1',
      'auth_user_id': 'user-1',
      'auth_device_id': 'device-1',
      'auth_email': 'me@example.com',
    });
  });

  test('deleteToken signs out but keeps ids, email, device key and pins (spec §5.2)', () async {
    await storage.save(session);
    await store.write(DeviceIdentity.storageKey, 'private-key');
    await store.write('pinned_machines_user-1', '[]');

    await storage.deleteToken();

    expect(await storage.load(), isNull);
    expect(await storage.lastEmail(), 'me@example.com');
    expect(
      store.values.keys,
      unorderedEquals(['auth_user_id', 'auth_device_id', 'auth_email', 'device_private_key', 'pinned_machines_user-1']),
    );
  });

  test("forgetAccount removes the session, the device key and only this user's pins", () async {
    await storage.save(session);
    await store.write(DeviceIdentity.storageKey, 'private-key');
    await store.write('pinned_machines_user-1', '[]');
    await store.write('pinned_machines_user-2', '[]');

    await storage.forgetAccount('user-1');

    expect(store.values, {'pinned_machines_user-2': '[]'});
  });

  test('the session never prints its token', () {
    expect(session.toString(), isNot(contains('token-1')));
  });
}
```

`apps/mobile/test/core/dependency_test.dart` (reads the committed, generated `dependency.config.dart`):

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // `dependency.config.dart` is generated by injectable and committed.
  final config = File('lib/core/dependency/dependency.config.dart').readAsStringSync();

  test('one shared KeyValueStore for the whole app (overview §5.5)', () {
    final registrations = [
      for (final match in RegExp(r'gh\.(\w+)<_i\d+\.KeyValueStore>\(').allMatches(config)) match[1],
    ];
    expect(registrations, ['lazySingletonAsync']);
  });

  test('settings load before the app starts', () {
    expect(config, matches(RegExp(r'lazySingletonAsync<_i\d+\.AppSettings>')));
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd apps/mobile && flutter test test/core/platform test/core/settings test/core/auth test/core/dependency_test.dart`
Expected: FAIL — compilation errors (`SecureKeyValueStore`, `AppSettings`, `AuthStorageImpl`, … are not defined) and `dependency_test.dart` finds no `KeyValueStore` registration.

- [ ] **Step 3: Configuration and platform adapters**

`apps/mobile/lib/core/config/app_config.dart`:

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

  /// "Mở App Store": the listing URL is only known after the first App Store submission, so the
  /// release build passes `--dart-define=SHELLX_APP_STORE_URL=https://apps.apple.com/app/id…`;
  /// until then the landing page (which links both stores) opens.
  static final Uri appStorePage = Uri.parse(
    const String.fromEnvironment('SHELLX_APP_STORE_URL', defaultValue: 'https://shellx.pro/'),
  );

  /// "Mở Google Play": the listing of `pro.shellx.mobile`.
  static final Uri playStorePage = Uri.parse('https://play.google.com/store/apps/details?id=pro.shellx.mobile');

  /// Linked from the registration form (spec §3.1, §11).
  static final Uri termsPage = Uri.parse('https://shellx.pro/terms');
  static final Uri privacyPage = Uri.parse('https://shellx.pro/privacy');
}

/// `https://relay.shellx.pro` → `wss://relay.shellx.pro/v1/ws` (spec §6.1).
/// A plain `http` base (local `wrangler dev`) maps to `ws`.
Uri relayWebSocketUri(Uri base) => base.replace(scheme: base.scheme == 'http' ? 'ws' : 'wss', path: '/v1/ws');
```

`apps/mobile/lib/core/platform/secure_key_value_store.dart`:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shellx_core/shellx_core.dart';

/// [KeyValueStore] backed by the iOS Keychain / Android Keystore (spec §5.1, §9.5).
///
/// The app registers exactly one instance (`Module.keyValueStore`, a lazy singleton): the
/// "one key even for concurrent calls" guarantee of `DeviceIdentity.loadOrCreate` only holds for
/// calls on the same instance (overview §5.5).
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

`apps/mobile/lib/core/platform/fresh_install.dart`:

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

`apps/mobile/lib/core/platform/device_description.dart`:

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

`apps/mobile/lib/core/platform/external_links.dart`:

```dart
import 'package:app_settings/app_settings.dart' as system;
import 'package:injectable/injectable.dart';
import 'package:url_launcher/url_launcher.dart';

/// Leaves the app: a web page (store listing, terms) or the phone's settings for ShellX
/// (camera permission, design "Quét mã").
abstract interface class ExternalLinks {
  Future<bool> open(Uri url);

  Future<void> openAppSettings();
}

@LazySingleton(as: ExternalLinks)
final class UrlLauncherLinks implements ExternalLinks {
  @override
  Future<bool> open(Uri url) => launchUrl(url, mode: LaunchMode.externalApplication);

  @override
  Future<void> openAppSettings() => system.AppSettings.openAppSettings();
}
```

- [ ] **Step 4: Settings and account storage**

`apps/mobile/lib/core/settings/app_settings.dart`:

```dart
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';

/// User preferences (spec §9.2 #5), as signals. Stored in the same secure store as the account
/// so the app has a single persistence mechanism.
@lazySingleton
class AppSettings {
  AppSettings(this._store);

  static const String fontSizeKey = 'settings_font_size';
  static const String biometricLockKey = 'settings_biometric_lock';
  static const double defaultFontSize = 14;
  static const double minFontSize = 8;
  static const double maxFontSize = 32;

  final KeyValueStore _store;
  final Signal<double> _fontSize = signal(defaultFontSize);

  /// Spec §5.6: the biometric lock is on by default.
  final Signal<bool> _biometricLock = signal(true);

  ReadonlySignal<double> get fontSize => _fontSize;
  ReadonlySignal<bool> get biometricLock => _biometricLock;

  static double clampFontSize(double value) => value.clamp(minFontSize, maxFontSize).toDouble();

  @PostConstruct(preResolve: true)
  Future<void> load() async {
    final storedSize = double.tryParse(await _store.read(fontSizeKey) ?? '');
    final biometricLock = await _store.read(biometricLockKey) != 'false';
    batch(() {
      _fontSize.value = clampFontSize(storedSize ?? defaultFontSize);
      _biometricLock.value = biometricLock;
    });
  }

  Future<void> setFontSize(double value) async {
    _fontSize.value = clampFontSize(value);
    await _store.write(fontSizeKey, _fontSize.peek().toString());
  }

  Future<void> setBiometricLock(bool enabled) async {
    _biometricLock.value = enabled;
    await _store.write(biometricLockKey, enabled.toString());
  }
}
```

`apps/mobile/lib/core/auth/account_session.dart`:

```dart
import 'package:equatable/equatable.dart';

/// The signed-in account as persisted in secure storage (spec §9.5). One opaque device token,
/// no refresh token.
final class AccountSession extends Equatable {
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

  @override
  List<Object?> get props => [userId, deviceId, token, email];

  /// Never includes the token: a session must not end up in a log line with it (overview §2).
  @override
  String toString() => 'AccountSession(userId: $userId, deviceId: $deviceId)';
}
```

`apps/mobile/lib/core/auth/auth_storage.dart`:

```dart
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';

/// Persistence of the signed-in account (spec §5.2, §9.5).
abstract class AuthStorage {
  static const String tokenKey = 'auth_token';
  static const String userIdKey = 'auth_user_id';
  static const String deviceIdKey = 'auth_device_id';
  static const String emailKey = 'auth_email';

  /// The saved session, or null when signed out.
  Future<AccountSession?> load();

  /// The email of the last account, kept after sign-out to prefill the login form.
  Future<String?> lastEmail();

  Future<void> save(AccountSession session);

  /// Spec §5.2: logging out on mobile deletes only the token. The device key
  /// and the machines pinned under `pinned_machines_<userId>` are kept so the
  /// same account can sign in again without re-pairing.
  Future<void> deleteToken();

  /// After `DELETE /v1/account`: forget everything tied to the deleted
  /// account — the session, the device private key and the machines pinned
  /// for [userId] (key `pinned_machines_<userId>`, overview §5.7).
  Future<void> forgetAccount(String userId);
}

@LazySingleton(as: AuthStorage)
class AuthStorageImpl implements AuthStorage {
  AuthStorageImpl(this._store);

  final KeyValueStore _store;

  @override
  Future<AccountSession?> load() async {
    final token = await _store.read(AuthStorage.tokenKey);
    final userId = await _store.read(AuthStorage.userIdKey);
    final deviceId = await _store.read(AuthStorage.deviceIdKey);
    final email = await _store.read(AuthStorage.emailKey);
    if (token == null || userId == null || deviceId == null || email == null) return null;
    return AccountSession(userId: userId, deviceId: deviceId, token: token, email: email);
  }

  @override
  Future<String?> lastEmail() => _store.read(AuthStorage.emailKey);

  @override
  Future<void> save(AccountSession session) async {
    await _store.write(AuthStorage.userIdKey, session.userId);
    await _store.write(AuthStorage.deviceIdKey, session.deviceId);
    await _store.write(AuthStorage.emailKey, session.email);
    await _store.write(AuthStorage.tokenKey, session.token);
  }

  @override
  Future<void> deleteToken() => _store.delete(AuthStorage.tokenKey);

  @override
  Future<void> forgetAccount(String userId) async {
    for (final key in [AuthStorage.tokenKey, AuthStorage.userIdKey, AuthStorage.deviceIdKey, AuthStorage.emailKey]) {
      await _store.delete(key);
    }
    await _store.delete(DeviceIdentity.storageKey);
    await _store.delete('pinned_machines_$userId');
  }
}
```

- [ ] **Step 5: Register them**

`apps/mobile/lib/core/dependency/module.dart` (replace the whole file):

```dart
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/config/app_config.dart';
import 'package:shellx_mobile/core/platform/device_description.dart';
import 'package:shellx_mobile/core/platform/fresh_install.dart';
import 'package:shellx_mobile/core/platform/secure_key_value_store.dart';
import 'package:shellx_mobile/core/router/app_router.dart';

@module
abstract class Module {
  @lazySingleton
  @preResolve
  Future<SharedPreferences> get sharedPref => SharedPreferences.getInstance();

  /// The one [KeyValueStore] of the app (overview §5.5). The first launch of a fresh install
  /// wipes the Keychain before anything reads it (spec §5.1).
  @lazySingleton
  @preResolve
  Future<KeyValueStore> keyValueStore(SharedPreferences prefs) async {
    final store = SecureKeyValueStore();
    await wipeSecureStorageOnFreshInstall(prefs: prefs, wipe: store.deleteAll);
    return store;
  }

  @lazySingleton
  @preResolve
  Future<DeviceDescription> get deviceDescription => describeThisDevice();

  @lazySingleton
  @preResolve
  Future<PackageInfo> get packageInfo => PackageInfo.fromPlatform();

  /// REST goes only through `shellx_core` (`package:http`), never through a second HTTP stack.
  @lazySingleton
  ShellxApi get api => ShellxApi(baseUri: AppConfig.relayBaseUri);

  @injectable
  BuildContext context(AppRouter appRouter) {
    final context = appRouter.navigatorKey.currentContext!;
    return context;
  }
}
```

`apps/mobile/lib/core/core.dart` (replace the whole file):

```dart
export 'dependency/dependency.dart';
export 'design/app_colors.dart';
export 'design/dark_colors.dart';
export 'design/light_colors.dart';
export 'design/typography.dart';
export 'design/design_system.dart';
export 'design/theme_data_factory.dart';
export 'design/terminal_colors.dart';
export 'extensions/adaptive_theme_mode_x.dart';
export 'router/app_router.dart';
export 'architecture/error.dart';
export 'architecture/error_factory.dart';
export 'architecture/controller.dart';
export 'architecture/state_signal.dart';
export 'handler/popup_handler.dart';
export 'architecture/page_domain.dart';
export 'architecture/paging_state_signal.dart';
export 'architecture/state.dart';
export 'router/app_router.gr.dart';
export 'handler/event_notifier.dart';
export 'router/app_transparent_route.dart';
export 'router/app_route_observer.dart';
// ShellX
export 'auth/account_session.dart';
export 'auth/auth_storage.dart';
export 'config/app_config.dart';
export 'platform/device_description.dart';
export 'platform/external_links.dart';
export 'platform/fresh_install.dart';
export 'platform/secure_key_value_store.dart';
export 'settings/app_settings.dart';

// 3rd party
export 'package:auto_route/auto_route.dart';
export 'package:flutter/material.dart';
export 'package:get_it/get_it.dart';
export 'package:injectable/injectable.dart';
export 'package:signals_flutter/signals_flutter.dart';
export 'package:equatable/equatable.dart';
```

- [ ] **Step 6: Generate, run the tests, analyze**

```bash
cd apps/mobile
dart run build_runner build
flutter test test/core/platform test/core/settings test/core/auth test/core/dependency_test.dart
flutter analyze
flutter test
```

Expected: `+15: All tests passed!`; `No issues found!`; `+161: All tests passed!`.

- [ ] **Step 7: Commit**

```bash
git add apps/mobile
git commit -m "feat(mobile): secure store, fresh-install wipe, device name, links, settings and account storage"
```

---

### Task 4: Biometric lock (spec §5.6) — controller, lock screen overlay, launch hook

UI per the design's "Khóa sinh trắc" screen: logo, "ShellX đang khóa", the subtitle, a status circle with the method's icon and one button "Mở khóa bằng {method}" (Face ID, Touch ID, vân tay, sinh trắc học or mã máy — whatever the device has).

**Files:**
- Create: `apps/mobile/lib/features/lock/domain/biometric_authenticator.dart`
- Create: `apps/mobile/lib/features/lock/presentation/app_lock_controller.dart`, `biometric_method.dart`, `lock_gate.dart`
- Create: `apps/mobile/lib/features/app/launch.dart`
- Modify: `apps/mobile/lib/features/app/splash_page.dart` (runs `prepareLaunch()` instead of the base's one-second delay), `apps/mobile/lib/features/app/app.dart` (installs `LockGate`)
- Test: `apps/mobile/test/features/lock/app_lock_controller_test.dart`, `apps/mobile/test/features/lock/lock_gate_test.dart`, `apps/mobile/test/support/fake_biometrics.dart`

**Interfaces:**
- Consumes: `AppSettings.biometricLock` (Task 3), `Controller`, `StatusCircle`, `ShellxLogo`, `AppButton` (Tasks 1–2).
- Produces: `enum BiometricKind { faceId, touchId, fingerprint, biometrics, passcode }`; `BiometricAuthenticator` (`isAvailable()`, `kind()`, `authenticate(reason)`) with `@LazySingleton(as:)` `LocalAuthBiometricAuthenticator`; `AppLockController({authenticator, isEnabled, now, backgroundTimeout = 5 min})` (`@lazySingleton` via the static `@factoryMethod create(BiometricAuthenticator, AppSettings)`): signals `isLocked`, `isAuthenticating`, `kind`; `detectKind()`, `lockOnLaunch()`, `onBackgrounded()`, `onForegrounded()`, `unlock(reason) → Future<bool>`, `settingChanged()`; `biometricMethod(S, BiometricKind)`, `biometricIcon(BiometricKind)`; `LockGate({lock, child, onBackground, onForeground})`, `LockScreen({lock})`; `prepareLaunch()` (Task 19 adds the version gate and the session restore).

- [ ] **Step 1: Write the failing tests**

`apps/mobile/test/support/fake_biometrics.dart`:

```dart
import 'package:shellx_mobile/features/lock/domain/biometric_authenticator.dart';

class FakeBiometricAuthenticator implements BiometricAuthenticator {
  bool available = true;
  bool result = true;
  BiometricKind kindValue = BiometricKind.faceId;
  int prompts = 0;
  String? lastReason;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<BiometricKind> kind() async => kindValue;

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    lastReason = reason;
    return result;
  }
}
```

`apps/mobile/test/features/lock/app_lock_controller_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/features/lock/presentation/app_lock_controller.dart';

import '../../support/fake_biometrics.dart';

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
    expect(lock.isLocked.value, isTrue);
    enabled = false;
    expect((controller()..lockOnLaunch()).isLocked.value, isFalse);
  });

  test('exactly 5 minutes in the background does not lock; more than 5 does', () {
    final lock = controller();
    lock.onBackgrounded();
    now = now.add(const Duration(minutes: 5));
    lock.onForegrounded();
    expect(lock.isLocked.value, isFalse);

    lock.onBackgrounded();
    now = now.add(const Duration(minutes: 5, seconds: 1));
    lock.onForegrounded();
    expect(lock.isLocked.value, isTrue);
  });

  test('a resume without a preceding pause never locks', () {
    final lock = controller();
    now = now.add(const Duration(hours: 1));
    lock.onForegrounded();
    expect(lock.isLocked.value, isFalse);
  });

  test('does not lock after a long background when the setting is off', () {
    enabled = false;
    final lock = controller()..onBackgrounded();
    now = now.add(const Duration(hours: 1));
    lock.onForegrounded();
    expect(lock.isLocked.value, isFalse);
  });

  test('unlock succeeds only when authentication succeeds', () async {
    final lock = controller()..lockOnLaunch();
    auth.result = false;
    expect(await lock.unlock('Unlock ShellX'), isFalse);
    expect(lock.isLocked.value, isTrue);
    auth.result = true;
    expect(await lock.unlock('Unlock ShellX'), isTrue);
    expect(lock.isLocked.value, isFalse);
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
    expect(lock.isLocked.value, isFalse);
  });
}
```

`apps/mobile/test/features/lock/lock_gate_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/lock/domain/biometric_authenticator.dart';
import 'package:shellx_mobile/features/lock/presentation/app_lock_controller.dart';
import 'package:shellx_mobile/features/lock/presentation/lock_gate.dart';

import '../../support/app_harness.dart';
import '../../support/fake_biometrics.dart';

void main() {
  late FakeBiometricAuthenticator auth;
  late DateTime now;
  late AppLockController lock;
  late int backgrounds;
  late int foregrounds;

  Widget app() => localized(
    const Scaffold(body: Text('secret terminal')),
    builder: (context, child) => LockGate(
      lock: lock,
      onBackground: () => backgrounds++,
      onForeground: () => foregrounds++,
      child: child!,
    ),
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

  setUp(() async {
    auth = FakeBiometricAuthenticator()..result = false;
    now = DateTime(2026, 9, 25, 9);
    lock = AppLockController(authenticator: auth, isEnabled: () => true, now: () => now);
    await lock.detectKind();
    backgrounds = 0;
    foregrounds = 0;
  });

  testWidgets('shows the lock screen on launch and prompts immediately', (tester) async {
    lock.lockOnLaunch();
    await tester.pumpWidget(app());
    await tester.pump();

    expect(find.text('ShellX đang khóa'), findsOneWidget);
    expect(find.text('Mở khóa để xem các máy và phiên terminal của bạn.'), findsOneWidget);
    expect(auth.prompts, 1);
    expect(auth.lastReason, 'Mở khóa ShellX');

    auth.result = true;
    await tester.tap(find.text('Mở khóa bằng Face ID'));
    await tester.pump();
    expect(find.text('ShellX đang khóa'), findsNothing);
    expect(find.text('secret terminal'), findsOneWidget);
  });

  testWidgets('relocks after more than 5 minutes in the background and reports both transitions', (tester) async {
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

  testWidgets('the button names the method the device has', (tester) async {
    auth.kindValue = BiometricKind.fingerprint;
    await lock.detectKind();
    lock.lockOnLaunch();
    await tester.pumpWidget(app());
    await tester.pump();
    expect(find.text('Mở khóa bằng vân tay'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd apps/mobile && flutter test test/features/lock`
Expected: FAIL — compilation errors (`BiometricAuthenticator`, `AppLockController`, `LockGate` are not defined).

- [ ] **Step 3: Authenticator and controller**

`apps/mobile/lib/features/lock/domain/biometric_authenticator.dart`:

```dart
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:local_auth/local_auth.dart';

/// What the lock asks for; names the unlock button ("Mở khóa bằng Face ID") and the setting.
enum BiometricKind { faceId, touchId, fingerprint, biometrics, passcode }

/// Face ID / fingerprint / device passcode (spec §5.6).
abstract interface class BiometricAuthenticator {
  /// False when the device has no passcode and no biometrics enrolled.
  Future<bool> isAvailable();

  Future<BiometricKind> kind();

  /// True when the user proved their identity.
  Future<bool> authenticate(String reason);
}

@LazySingleton(as: BiometricAuthenticator)
final class LocalAuthBiometricAuthenticator implements BiometricAuthenticator {
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<BiometricKind> kind() async {
    final List<BiometricType> types;
    try {
      types = await _auth.getAvailableBiometrics();
    } on PlatformException {
      return BiometricKind.passcode;
    }
    if (Platform.isIOS) {
      if (types.contains(BiometricType.face)) return BiometricKind.faceId;
      if (types.contains(BiometricType.fingerprint)) return BiometricKind.touchId;
      return BiometricKind.passcode;
    }
    // Android usually reports only strong/weak classes.
    if (types.contains(BiometricType.fingerprint)) return BiometricKind.fingerprint;
    return types.isEmpty ? BiometricKind.passcode : BiometricKind.biometrics;
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

`apps/mobile/lib/features/lock/presentation/app_lock_controller.dart`:

```dart
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/lock/domain/biometric_authenticator.dart';

/// Spec §5.6: require unlocking when the app opens and when it comes back
/// after more than 5 minutes in the background. One instance for the app.
@lazySingleton
class AppLockController extends Controller {
  AppLockController({
    required BiometricAuthenticator authenticator,
    required bool Function() isEnabled,
    DateTime Function()? now,
    this.backgroundTimeout = const Duration(minutes: 5),
  }) : _authenticator = authenticator,
       _isEnabled = isEnabled,
       _now = now ?? DateTime.now;

  @factoryMethod
  static AppLockController create(BiometricAuthenticator authenticator, AppSettings settings) =>
      AppLockController(authenticator: authenticator, isEnabled: () => settings.biometricLock.peek());

  final BiometricAuthenticator _authenticator;
  final bool Function() _isEnabled;
  final DateTime Function() _now;
  final Duration backgroundTimeout;
  final Signal<bool> _locked = signal(false);
  final Signal<bool> _authenticating = signal(false);
  final Signal<BiometricKind> _kind = signal(BiometricKind.passcode);
  DateTime? _backgroundedAt;

  ReadonlySignal<bool> get isLocked => _locked;
  ReadonlySignal<bool> get isAuthenticating => _authenticating;

  /// Face ID, Touch ID, fingerprint… — names the unlock button and the setting.
  ReadonlySignal<BiometricKind> get kind => _kind;

  Future<void> detectKind() async => _kind.value = await _authenticator.kind();

  void lockOnLaunch() {
    if (_isEnabled()) _locked.value = true;
  }

  void onBackgrounded() => _backgroundedAt = _now();

  void onForegrounded() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (since == null || !_isEnabled()) return;
    if (_now().difference(since) > backgroundTimeout) _locked.value = true;
  }

  /// Prompts for Face ID / fingerprint / passcode. Unlocks without a prompt
  /// when the device cannot authenticate at all.
  Future<bool> unlock(String reason) async {
    if (!_locked.peek()) return true;
    if (_authenticating.peek()) return false;
    _authenticating.value = true;
    try {
      final ok = !await _authenticator.isAvailable() || await _authenticator.authenticate(reason);
      if (ok) _locked.value = false;
      return ok;
    } finally {
      _authenticating.value = false;
    }
  }

  /// Call after the biometric setting changes: turning it off while locked
  /// must not leave the user stuck.
  void settingChanged() {
    if (!_isEnabled()) _locked.value = false;
  }
}
```

`apps/mobile/lib/features/lock/presentation/biometric_method.dart`:

```dart
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/lock/domain/biometric_authenticator.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// "Face ID", "Touch ID", "vân tay", "sinh trắc học" or "mã máy".
String biometricMethod(S strings, BiometricKind kind) => switch (kind) {
  BiometricKind.faceId => strings.biometricFaceId,
  BiometricKind.touchId => strings.biometricTouchId,
  BiometricKind.fingerprint => strings.biometricFingerprint,
  BiometricKind.biometrics => strings.biometricGeneric,
  BiometricKind.passcode => strings.biometricPasscode,
};

IconData biometricIcon(BiometricKind kind) => switch (kind) {
  BiometricKind.faceId => Icons.face_outlined,
  BiometricKind.touchId || BiometricKind.fingerprint || BiometricKind.biometrics => Icons.fingerprint,
  BiometricKind.passcode => Icons.lock_outline,
};
```

- [ ] **Step 4: Lock screen overlay**

`apps/mobile/lib/features/lock/presentation/lock_gate.dart`:

```dart
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/lock/presentation/app_lock_controller.dart';
import 'package:shellx_mobile/features/lock/presentation/biometric_method.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Covers the whole app with [LockScreen] while [lock] is locked and feeds
/// app lifecycle changes to the lock and to [onBackground]/[onForeground].
///
/// It wraps the router's navigator (`MaterialApp.router(builder:)`), not a route: the lock must
/// also engage when the app returns from the background, which is no navigation event.
class LockGate extends StatefulWidget {
  const LockGate({
    super.key,
    required this.lock,
    required this.child,
    this.onBackground,
    this.onForeground,
  });

  final AppLockController lock;
  final Widget child;

  /// Called when the app is paused (suspend the relay, spec §12).
  final VoidCallback? onBackground;

  /// Called every time the app returns to the foreground (reconnect, spec §9.4).
  final VoidCallback? onForeground;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> {
  late final AppLifecycleListener _lifecycle;
  late final void Function() _stopUnfocus;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onPause: _onPause, onResume: _onResume);
    // Keep keystrokes (soft or hardware keyboard) away from the hidden terminal.
    _stopUnfocus = widget.lock.isLocked.subscribe((locked) {
      if (locked) FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  void _onPause() {
    widget.lock.onBackgrounded();
    widget.onBackground?.call();
  }

  void _onResume() {
    widget.lock.onForegrounded();
    widget.onForeground?.call();
  }

  @override
  void dispose() {
    _stopUnfocus();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final locked = widget.lock.isLocked.value;
      return Stack(
        children: [
          ExcludeFocus(excluding: locked, child: widget.child),
          if (locked) Positioned.fill(child: LockScreen(lock: widget.lock)),
        ],
      );
    });
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
    await widget.lock.unlock(S.of(context).lockReason);
  }

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Watch((context) {
              final kind = widget.lock.kind.value;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ShellxLogo(),
                  18.sizedHeight,
                  Text(strings.lockTitle, textAlign: TextAlign.center, style: context.typo.heading26.heavy),
                  12.sizedHeight,
                  Text(
                    strings.lockSubtitle,
                    textAlign: TextAlign.center,
                    style: context.typo.subHeader15.copyWith(color: context.colors.secondaryText),
                  ),
                  28.sizedHeight,
                  StatusCircle(icon: biometricIcon(kind)),
                  32.sizedHeight,
                  AppButton(
                    title: strings.lockUnlockWith(biometricMethod(strings, kind)),
                    width: double.infinity,
                    state: widget.lock.isAuthenticating.value ? ButtonState.loading : ButtonState.available,
                    onTap: _unlock,
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Lock on launch and cover every route**

`apps/mobile/lib/features/app/launch.dart`:

```dart
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/lock/presentation/app_lock_controller.dart';

/// Everything between dependency injection and the first route.
Future<void> prepareLaunch() async {
  // Spec §5.6: locked when the app opens (if enabled).
  final lock = getIt<AppLockController>();
  await lock.detectKind();
  lock.lockOnLaunch();
}
```

Edit `apps/mobile/lib/features/app/splash_page.dart` — replace:

```dart
import 'package:shellx_mobile/core/core.dart';
import 'app.dart';
```

with:

```dart
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/app/launch.dart';

import 'app.dart';
```

Edit `apps/mobile/lib/features/app/splash_page.dart` — replace:

```dart
    await Future.delayed(const Duration(seconds: 1));
```

with:

```dart
    await prepareLaunch();
```

Edit `apps/mobile/lib/features/app/app.dart` — replace:

```dart
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/shared/shared.dart';
```

with:

```dart
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/lock/presentation/app_lock_controller.dart';
import 'package:shellx_mobile/features/lock/presentation/lock_gate.dart';
import 'package:shellx_mobile/shared/shared.dart';
```

Edit `apps/mobile/lib/features/app/app.dart` — replace:

```dart
  final appRouter = getIt<AppRouter>();
```

with:

```dart
  final appRouter = getIt<AppRouter>();
  final lock = getIt<AppLockController>();
```

Edit `apps/mobile/lib/features/app/app.dart` — replace:

```dart
          theme: ThemeDataFactory.create(computedBrightness),
```

with:

```dart
          theme: ThemeDataFactory.create(computedBrightness),
          // Spec §5.6: the lock covers every route and dialog.
          builder: (context, child) => LockGate(lock: lock, child: child!),
```

- [ ] **Step 6: Generate, run the tests, analyze**

```bash
cd apps/mobile
dart run build_runner build
flutter test test/features/lock
flutter analyze
flutter test
```

Expected: `+10: All tests passed!`; `No issues found!`; `+171: All tests passed!`.

- [ ] **Step 7: Commit**

```bash
git add apps/mobile
git commit -m "feat(mobile): biometric lock on launch and after 5 minutes in the background"
```

---

### Task 5: Terminal input primitives — cursor keys, control characters, newlines, shortcuts

**Files:**
- Create: `apps/mobile/lib/features/terminal/domain/terminal_input.dart`, `apps/mobile/lib/features/terminal/presentation/terminal_shortcuts.dart`
- Test: `apps/mobile/test/features/terminal/terminal_input_test.dart`

**Interfaces:**
- Consumes: `package:xterm/core.dart` — `Terminal`, `TerminalKey`, `TerminalInputHandler`, `TerminalKeyboardEvent` (`key`, `shift`, `alt`, `ctrl`, `state.cursorKeysMode`), `CascadeInputHandler`, `defaultInputHandler`.
- Produces:
  - `final class CursorKeysInputHandler implements TerminalInputHandler { const CursorKeysInputHandler(); }` and `const TerminalInputHandler shellxInputHandler` (= `CascadeInputHandler([CursorKeysInputHandler(), defaultInputHandler])`)
  - `String? controlCharacterFor(String char)`, `String applyModifiersToText(String text, {required bool ctrl, required bool alt})`, `String normalizeTypedText(String text)`, `String normalizePastedText(String text)`
  - `Map<ShortcutActivator, Intent> terminalShortcuts(TargetPlatform platform)`

Why: verified in xterm 4.0.0's `KeytabInputHandler` — it passes `appKeypadMode` as `appCursorKeys`, so a program that sends only `ESC[?1h` still gets `ESC[A`; Alt+Left and Shift+Up come out as `ESC[1;5D`/`ESC[1;5A`, Ctrl+Alt+Left produces nothing. `charInput` ignores uppercase with Ctrl and sends Alt+a as `ESC A` (uppercase). This task keeps xterm's handler for every other key and replaces only those behaviours (Review Focus 3, 4). Pure functions — no signals or DI here.

- [ ] **Step 1: Write the failing test**

`apps/mobile/test/features/terminal/terminal_input_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/features/terminal/domain/terminal_input.dart';
import 'package:shellx_mobile/features/terminal/presentation/terminal_shortcuts.dart';
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

- [ ] **Step 2: Run it to see it fail**

Run: `cd apps/mobile && flutter test test/features/terminal/terminal_input_test.dart`
Expected: FAIL — `Error when reading 'lib/features/terminal/domain/terminal_input.dart': No such file or directory` (and the same for `terminal_shortcuts.dart`).

- [ ] **Step 3: Implement**

`apps/mobile/lib/features/terminal/domain/terminal_input.dart`:

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
const TerminalInputHandler shellxInputHandler = CascadeInputHandler([CursorKeysInputHandler(), defaultInputHandler]);

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

`apps/mobile/lib/features/terminal/presentation/terminal_shortcuts.dart`:

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
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true): const PasteTextIntent(
          SelectionChangedCause.keyboard,
        ),
      };
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      return {
        const SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true): CopySelectionTextIntent.copy,
        const SingleActivator(LogicalKeyboardKey.keyV, control: true, shift: true): const PasteTextIntent(
          SelectionChangedCause.keyboard,
        ),
      };
  }
}
```

- [ ] **Step 4: Run the test and the analyzer**

```bash
cd apps/mobile
flutter test test/features/terminal/terminal_input_test.dart
flutter analyze
```

Expected: `+8: All tests passed!`; `No issues found!`. (The whole suite: `+179`.)

- [ ] **Step 5: Commit**

```bash
git add apps/mobile
git commit -m "feat(mobile): terminal input fixes for DECCKM, modified arrows and shortcuts"
```

---

### Task 6: `ExtraKeysController` — sticky Ctrl/Alt and key dispatch (spec §9.3)

**Files:**
- Create: `apps/mobile/lib/features/terminal/presentation/controllers/extra_keys_controller.dart`
- Test: `apps/mobile/test/features/terminal/extra_keys_controller_test.dart`

**Interfaces:**
- Consumes: `Terminal.keyInput(TerminalKey key, {bool shift, bool alt, bool ctrl})`, `Terminal.onOutput`; `applyModifiersToText`, `shellxInputHandler` (Task 5); the base `Controller`.
- Produces:
  - `enum ExtraKey { esc, tab, ctrl, alt, up, down, left, right, pipe, tilde, slash, minus, home, end, pageUp, pageDown, paste }` and `String? extraKeyLabel(ExtraKey key)` (null for `paste`, which is localised)
  - `enum ModifierLatch { off, oneShot, locked }`
  - `abstract interface class ModifierSource { bool get hasActiveModifiers; ({bool ctrl, bool alt}) consumeModifiers(); String applyModifiers(String text); }`
  - `class ExtraKeysController extends Controller implements ModifierSource { ExtraKeysController({DateTime Function()? now, Duration doubleTapWindow = const Duration(milliseconds: 400)}); ReadonlySignal<ModifierLatch> get ctrl; ReadonlySignal<ModifierLatch> get alt; void tapModifier(ExtraKey key); void sendKey(ExtraKey key, Terminal terminal); void dispose(); }` — not registered in DI: each `TerminalWorkspace` (Task 13) owns one.

Sticky semantics: off →(tap)→ one-shot; one-shot →(second tap within 400 ms)→ locked; one-shot →(slower tap)→ off (cancel); locked →(tap)→ off. A one-shot modifier is consumed by the next key from any source (extra key, soft keyboard, hardware keyboard); locked stays. Navigation keys go through `Terminal.keyInput` so xterm applies the cursor mode; characters go straight to `onOutput` because `ShellxTerminal.textInput` (Task 7) would apply the modifiers a second time. The latches are signals, so the bar (Task 7) redraws with `Watch`.

- [ ] **Step 1: Write the failing test**

`apps/mobile/test/features/terminal/extra_keys_controller_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/core/core.dart' show effect;
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:shellx_mobile/features/terminal/domain/terminal_input.dart';
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
    expect(
      ExtraKey.values.map((k) => extraKeyLabel(k) ?? 'Dán').join(' '),
      'Esc Tab Ctrl Alt ↑ ↓ ← → | ~ / - Home End PgUp PgDn Dán',
    );
  });

  group('sticky modifiers', () {
    test('one tap applies Ctrl to the next key only', () {
      keys.tapModifier(ExtraKey.ctrl);
      expect(keys.ctrl.value, ModifierLatch.oneShot);
      expect(keys.applyModifiers('c'), '\x03');
      expect(keys.ctrl.value, ModifierLatch.off);
      expect(keys.applyModifiers('c'), 'c');
    });

    test('a double tap locks until tapped again', () {
      keys.tapModifier(ExtraKey.ctrl);
      advance(200);
      keys.tapModifier(ExtraKey.ctrl);
      expect(keys.ctrl.value, ModifierLatch.locked);
      expect(keys.applyModifiers('c'), '\x03');
      expect(keys.applyModifiers('d'), '\x04');
      expect(keys.ctrl.value, ModifierLatch.locked);
      advance(5000);
      keys.tapModifier(ExtraKey.ctrl);
      expect(keys.ctrl.value, ModifierLatch.off);
      expect(keys.applyModifiers('c'), 'c');
    });

    test('the second tap must land inside the double-tap window', () {
      keys.tapModifier(ExtraKey.alt);
      advance(400);
      keys.tapModifier(ExtraKey.alt);
      expect(keys.alt.value, ModifierLatch.locked);

      keys.tapModifier(ExtraKey.alt); // unlock
      advance(1000);
      keys.tapModifier(ExtraKey.alt);
      advance(401);
      keys.tapModifier(ExtraKey.alt); // slow second tap cancels
      expect(keys.alt.value, ModifierLatch.off);
    });

    test('a quick tap after the one-shot was used arms a new one-shot, not a lock', () {
      keys.tapModifier(ExtraKey.ctrl);
      keys.applyModifiers('a');
      advance(100);
      keys.tapModifier(ExtraKey.ctrl);
      expect(keys.ctrl.value, ModifierLatch.oneShot);
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

    test('the latch signals change on taps and when a one-shot is consumed', () {
      final seen = <ModifierLatch>[];
      final stop = effect(() => seen.add(keys.ctrl.value));
      addTearDown(stop);
      keys.tapModifier(ExtraKey.ctrl);
      keys.consumeModifiers();
      keys.consumeModifiers();
      expect(seen, [ModifierLatch.off, ModifierLatch.oneShot, ModifierLatch.off]);
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

- [ ] **Step 2: Run it to see it fail**

Run: `cd apps/mobile && flutter test test/features/terminal/extra_keys_controller_test.dart`
Expected: FAIL — `Error when reading 'lib/features/terminal/presentation/controllers/extra_keys_controller.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/mobile/lib/features/terminal/presentation/controllers/extra_keys_controller.dart`:

```dart
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/terminal/domain/terminal_input.dart';
import 'package:xterm/core.dart';

/// The extra keys row of spec §9.3, in order.
enum ExtraKey {
  esc,
  tab,
  ctrl,
  alt,
  up,
  down,
  left,
  right,
  pipe,
  tilde,
  slash,
  minus,
  home,
  end,
  pageUp,
  pageDown,
  paste,
}

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

/// State of the extra keys bar: sticky Ctrl/Alt (as signals) and key dispatch.
///
/// Spec §9.3: tapping Ctrl/Alt once applies it to the next key only; a double
/// tap (second tap within [doubleTapWindow]) locks it until it is tapped
/// again. A slow second tap cancels a pending one-shot modifier.
class ExtraKeysController extends Controller implements ModifierSource {
  ExtraKeysController({
    DateTime Function()? now,
    this.doubleTapWindow = const Duration(milliseconds: 400),
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Duration doubleTapWindow;
  final Signal<ModifierLatch> _ctrl = signal(ModifierLatch.off);
  final Signal<ModifierLatch> _alt = signal(ModifierLatch.off);
  DateTime? _ctrlTappedAt;
  DateTime? _altTappedAt;

  ReadonlySignal<ModifierLatch> get ctrl => _ctrl;
  ReadonlySignal<ModifierLatch> get alt => _alt;

  void tapModifier(ExtraKey key) {
    final now = _now();
    switch (key) {
      case ExtraKey.ctrl:
        _ctrl.value = _nextLatch(_ctrl.peek(), _ctrlTappedAt, now);
        _ctrlTappedAt = now;
      case ExtraKey.alt:
        _alt.value = _nextLatch(_alt.peek(), _altTappedAt, now);
        _altTappedAt = now;
      default:
        throw ArgumentError.value(key, 'key', 'not a modifier key');
    }
  }

  ModifierLatch _nextLatch(ModifierLatch current, DateTime? lastTap, DateTime now) => switch (current) {
    ModifierLatch.off => ModifierLatch.oneShot,
    ModifierLatch.oneShot =>
      lastTap != null && now.difference(lastTap) <= doubleTapWindow ? ModifierLatch.locked : ModifierLatch.off,
    ModifierLatch.locked => ModifierLatch.off,
  };

  @override
  bool get hasActiveModifiers => _ctrl.peek() != ModifierLatch.off || _alt.peek() != ModifierLatch.off;

  @override
  ({bool ctrl, bool alt}) consumeModifiers() {
    final active = (ctrl: _ctrl.peek() != ModifierLatch.off, alt: _alt.peek() != ModifierLatch.off);
    batch(() {
      if (_ctrl.peek() == ModifierLatch.oneShot) _ctrl.value = ModifierLatch.off;
      if (_alt.peek() == ModifierLatch.oneShot) _alt.value = ModifierLatch.off;
    });
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

  void dispose() {
    _ctrl.dispose();
    _alt.dispose();
  }
}
```

- [ ] **Step 4: Run the test and the analyzer**

```bash
cd apps/mobile
flutter test test/features/terminal/extra_keys_controller_test.dart
flutter analyze
```

Expected: `+13: All tests passed!`; `No issues found!`. (The whole suite: `+192`.)

- [ ] **Step 5: Commit**

```bash
git add apps/mobile
git commit -m "feat(mobile): sticky Ctrl/Alt extra keys controller"
```

---

### Task 7: `ShellxTerminal` (soft keyboard + sticky modifiers + paste) and the extra keys bar

Design ("Phím phụ" in the terminal screens): a 50 pt row on the keyboard colour, key caps at least 46 pt wide; `Ctrl`/`Alt` armed once = a plain key with a 2.5 pt primary outline (`ValueKey('latch-one-shot')`), locked = filled primary with a small dot (`ValueKey('latch-locked')`).

**Files:**
- Create: `apps/mobile/lib/features/terminal/domain/shellx_terminal.dart`, `apps/mobile/lib/features/terminal/presentation/widgets/extra_keys_bar.dart`
- Test: `apps/mobile/test/features/terminal/shellx_terminal_test.dart`, `apps/mobile/test/features/terminal/extra_keys_bar_test.dart`

**Interfaces:**
- Consumes: `Terminal` (`keyInput`, `textInput`, `paste`, `bracketedPasteMode`), `TerminalKey`; `ModifierSource`, `ExtraKeysController`, `ExtraKey`, `ModifierLatch`, `extraKeyLabel` (Task 6); `shellxInputHandler`, `normalizeTypedText`, `normalizePastedText` (Task 5); `S.keyPaste`; `context.colors.keyboard*`, `primary` (Task 2).
- Produces:
  - `class ShellxTerminal extends Terminal { ShellxTerminal({required ModifierSource modifiers, int maxLines = 2000}); final ModifierSource modifiers; }` — overrides `keyInput` (applies pending sticky modifiers; returns `false` for text keys so `TerminalView` falls back to `textInput` with the typed character), `textInput` (Return → CR, then sticky modifiers), `paste` (CR line breaks, bracketed when enabled, never modified).
  - `class ExtraKeysBar extends StatelessWidget { const ExtraKeysBar({Key? key, required ExtraKeysController controller, required ValueChanged<ExtraKey> onKey, required VoidCallback onPaste}); static const double height = 50; }` — key caps keyed `ValueKey('extra-key-<name>')`.

- [ ] **Step 1: Write the failing tests**

`apps/mobile/test/features/terminal/shellx_terminal_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:shellx_mobile/features/terminal/domain/shellx_terminal.dart';
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
    expect(keys.alt.value, ModifierLatch.oneShot);
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
    expect(keys.ctrl.value, ModifierLatch.oneShot);
  });
}
```

`apps/mobile/test/features/terminal/extra_keys_bar_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/terminal/domain/shellx_terminal.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/widgets/extra_keys_bar.dart';

import '../../support/app_harness.dart';

void main() {
  late DateTime now;
  late ExtraKeysController keys;
  late ShellxTerminal terminal;
  late List<String> out;
  late int pastes;

  Widget bar() => localized(
    Scaffold(
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

  BoxDecoration capDecoration(WidgetTester tester, ExtraKey key) {
    final cap = find.descendant(
      of: keyCap(key),
      matching: find.byWidgetPredicate(
        (widget) => widget is Container && widget.decoration is BoxDecoration && widget.constraints?.minWidth == 46,
      ),
    );
    return tester.widget<Container>(cap).decoration! as BoxDecoration;
  }

  testWidgets('design: Ctrl once = primary outline on a plain key, locked = filled with a dot', (tester) async {
    final colors = Brightness.light.appColors;
    await tester.pumpWidget(bar());
    expect(capDecoration(tester, ExtraKey.ctrl).border, isNull);

    await tester.tap(keyCap(ExtraKey.ctrl));
    await tester.pump();
    final once = capDecoration(tester, ExtraKey.ctrl);
    expect(once.color, colors.keyboardKey);
    expect((once.border! as Border).top.color, colors.primary);
    expect(find.byKey(const ValueKey('latch-locked')), findsNothing);

    now = now.add(const Duration(milliseconds: 150));
    await tester.tap(keyCap(ExtraKey.ctrl));
    await tester.pump();
    final locked = capDecoration(tester, ExtraKey.ctrl);
    expect(locked.color, colors.primary);
    expect(locked.border, isNull);
    expect(
      find.descendant(of: keyCap(ExtraKey.ctrl), matching: find.byKey(const ValueKey('latch-locked'))),
      findsOneWidget,
    );
  });

  testWidgets('keys are 50 pt touch targets on the keyboard colour', (tester) async {
    await tester.pumpWidget(bar());
    expect(tester.getSize(keyCap(ExtraKey.esc)).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(find.byType(ExtraKeysBar)).height, ExtraKeysBar.height);
  });

  testWidgets('tap Ctrl then type c on the soft keyboard sends ^C', (tester) async {
    await tester.pumpWidget(bar());
    await tester.tap(keyCap(ExtraKey.ctrl));
    await tester.pump();
    expect(
      find.descendant(of: keyCap(ExtraKey.ctrl), matching: find.byKey(const ValueKey('latch-one-shot'))),
      findsOneWidget,
    );

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
    expect(
      find.descendant(of: keyCap(ExtraKey.ctrl), matching: find.byKey(const ValueKey('latch-locked'))),
      findsOneWidget,
    );

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

- [ ] **Step 2: Run them to see them fail**

Run: `cd apps/mobile && flutter test test/features/terminal/shellx_terminal_test.dart test/features/terminal/extra_keys_bar_test.dart`
Expected: FAIL — `Error when reading 'lib/features/terminal/domain/shellx_terminal.dart': No such file or directory` (and the same for `extra_keys_bar.dart`).

- [ ] **Step 3: Implement**

`apps/mobile/lib/features/terminal/domain/shellx_terminal.dart`:

```dart
import 'package:shellx_mobile/features/terminal/domain/terminal_input.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:xterm/core.dart';

/// Keys whose soft-keyboard text must reach [ShellxTerminal.textInput] so the
/// sticky modifiers keep the typed character's case.
const Set<TerminalKey> _textKeys = {
  TerminalKey.keyA,
  TerminalKey.keyB,
  TerminalKey.keyC,
  TerminalKey.keyD,
  TerminalKey.keyE,
  TerminalKey.keyF,
  TerminalKey.keyG,
  TerminalKey.keyH,
  TerminalKey.keyI,
  TerminalKey.keyJ,
  TerminalKey.keyK,
  TerminalKey.keyL,
  TerminalKey.keyM,
  TerminalKey.keyN,
  TerminalKey.keyO,
  TerminalKey.keyP,
  TerminalKey.keyQ,
  TerminalKey.keyR,
  TerminalKey.keyS,
  TerminalKey.keyT,
  TerminalKey.keyU,
  TerminalKey.keyV,
  TerminalKey.keyW,
  TerminalKey.keyX,
  TerminalKey.keyY,
  TerminalKey.keyZ,
  TerminalKey.digit0,
  TerminalKey.digit1,
  TerminalKey.digit2,
  TerminalKey.digit3,
  TerminalKey.digit4,
  TerminalKey.digit5,
  TerminalKey.digit6,
  TerminalKey.digit7,
  TerminalKey.digit8,
  TerminalKey.digit9,
  TerminalKey.space,
  TerminalKey.minus,
  TerminalKey.equal,
  TerminalKey.bracketLeft,
  TerminalKey.bracketRight,
  TerminalKey.backslash,
  TerminalKey.semicolon,
  TerminalKey.quote,
  TerminalKey.backquote,
  TerminalKey.comma,
  TerminalKey.period,
  TerminalKey.slash,
};

/// xterm [Terminal] that honours the extra keys bar's sticky Ctrl/Alt for
/// soft-keyboard and hardware-keyboard input.
///
/// `TerminalView` feeds soft-keyboard text as `keyInput(key)` first and falls
/// back to `textInput(text)` when that returns false; hardware keys arrive as
/// `keyInput(key, ctrl:, alt:, shift:)`.
class ShellxTerminal extends Terminal {
  ShellxTerminal({required this.modifiers, super.maxLines = 2000}) : super(inputHandler: shellxInputHandler);

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

`apps/mobile/lib/features/terminal/presentation/widgets/extra_keys_bar.dart`:

```dart
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// The horizontally scrolling extra keys row right above the keyboard (spec §9.3), styled like
/// the system keyboard (`--kb-*`). Ctrl/Alt: outline = once, filled with a dot = locked.
class ExtraKeysBar extends StatelessWidget {
  const ExtraKeysBar({super.key, required this.controller, required this.onKey, required this.onPaste});

  static const double height = 50;

  final ExtraKeysController controller;

  /// Every key except Ctrl, Alt and Paste.
  final ValueChanged<ExtraKey> onKey;
  final VoidCallback onPaste;

  void _press(ExtraKey key) {
    switch (key) {
      case ExtraKey.ctrl:
      case ExtraKey.alt:
        controller.tapModifier(key);
      case ExtraKey.paste:
        onPaste();
      default:
        onKey(key);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: context.colors.keyboardBackground,
        border: const Border(top: BorderSide(color: Color(0x14000000))),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 3),
        children: [
          for (final key in ExtraKey.values)
            Watch(
              key: ValueKey('extra-key-${key.name}'),
              (context) => _KeyCap(
                label: extraKeyLabel(key) ?? S.of(context).keyPaste,
                isPaste: key == ExtraKey.paste,
                latch: switch (key) {
                  ExtraKey.ctrl => controller.ctrl.value,
                  ExtraKey.alt => controller.alt.value,
                  _ => null,
                },
                onTap: () => _press(key),
              ),
            ),
        ],
      ),
    );
  }
}

class _KeyCap extends StatelessWidget {
  const _KeyCap({required this.label, required this.isPaste, required this.latch, required this.onTap});

  final String label;
  final bool isPaste;
  final ModifierLatch? latch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final once = latch == ModifierLatch.oneShot;
    final locked = latch == ModifierLatch.locked;
    final foreground = locked ? colors.onPrimary : (once ? colors.primary : colors.keyboardInk);
    final textStyle = isPaste
        ? context.typo.paragraph.bold.copyWith(color: foreground)
        : TextStyle(
            fontFamily: FontFamily.jetBrainsMono,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: foreground,
          );
    // The whole bar height (50 pt) is the touch target; the cap itself is 38 pt tall.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
        child: Container(
          key: once ? const ValueKey('latch-one-shot') : null,
          constraints: const BoxConstraints(minWidth: 46),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: locked ? colors.primary : colors.keyboardKey,
            borderRadius: BorderRadius.circular(9),
            border: once ? Border.all(color: colors.primary, width: 2.5) : null,
            boxShadow: const [BoxShadow(color: Color(0x47000000), offset: Offset(0, 1))],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Text(label, style: textStyle),
              if (locked)
                Positioned(
                  top: -8,
                  right: -6,
                  child: Container(
                    key: const ValueKey('latch-locked'),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: foreground, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests and the analyzer**

```bash
cd apps/mobile
flutter test test/features/terminal/shellx_terminal_test.dart test/features/terminal/extra_keys_bar_test.dart
flutter analyze
```

Expected: `+13: All tests passed!`; `No issues found!`. (The whole suite: `+205`.)

- [ ] **Step 5: Commit**

```bash
git add apps/mobile
git commit -m "feat(mobile): xterm terminal with sticky modifiers, paste, and the extra keys bar"
```

---

### Task 8: Grid measurement and pinch-to-zoom

**Files:**
- Create: `apps/mobile/lib/features/terminal/presentation/terminal_metrics.dart`, `apps/mobile/lib/features/terminal/presentation/widgets/pinch_zoom.dart`
- Test: `apps/mobile/test/features/terminal/terminal_metrics_test.dart`

**Interfaces:**
- Consumes: `TerminalStyle({fontSize, fontFamily})`, `TerminalStyle.toTextStyle()` (`package:xterm/xterm.dart`); `FontFamily.jetBrainsMono` (Task 1); `AppSettings.minFontSize/maxFontSize` (Task 3).
- Produces:
  - `typedef TerminalGrid = ({int cols, int rows});`, `const TerminalGrid fallbackGrid = (cols: 80, rows: 24);`, `TerminalStyle shellxTerminalStyle(double fontSize)`, `TerminalGrid? measureTerminalGrid(Size size, TerminalStyle style, TextScaler textScaler)`
  - `final class PinchZoomTracker { PinchZoomTracker({double min = 8, double max = 32, double step = 0.5}); void down(int pointer, Offset position, double currentSize); double? move(int pointer, Offset position); void up(int pointer); }`, `class PinchToZoom extends StatefulWidget { const PinchToZoom({Key? key, required double fontSize, required ValueChanged<double> onFontSize, required Widget child}); }`

`measureTerminalGrid` mirrors xterm's `calcCharSize` (width of `"mmmmmmmmmm"` ÷ 10, paragraph height) to size `session.open`/`session.attach` before the new `TerminalView` is laid out; the first layout then corrects the size through `resize`. `PinchToZoom` listens to raw pointers (translucent `Listener`) so it never steals the terminal's scroll/selection gestures.

- [ ] **Step 1: Write the failing test**

`apps/mobile/test/features/terminal/terminal_metrics_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/features/terminal/presentation/widgets/pinch_zoom.dart';
import 'package:shellx_mobile/features/terminal/presentation/terminal_metrics.dart';

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
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PinchToZoom(
          fontSize: 14,
          onFontSize: sizes.add,
          child: const SizedBox.expand(),
        ),
      ),
    );
    final first = await tester.startGesture(const Offset(300, 300), pointer: 1);
    final second = await tester.startGesture(const Offset(400, 300), pointer: 2);
    await second.moveTo(const Offset(500, 300));
    await first.up();
    await second.up();
    expect(sizes.last, 28);
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd apps/mobile && flutter test test/features/terminal/terminal_metrics_test.dart`
Expected: FAIL — `Error when reading 'lib/features/terminal/presentation/terminal_metrics.dart': No such file or directory` (and the same for `pinch_zoom.dart`).

- [ ] **Step 3: Implement**

`apps/mobile/lib/features/terminal/presentation/terminal_metrics.dart`:

```dart
import 'package:flutter/painting.dart';
import 'package:shellx_mobile/shared/shared.dart';
import 'package:xterm/xterm.dart';

typedef TerminalGrid = ({int cols, int rows});

/// Used when the viewport cannot fit one cell yet (Review Focus 4): the real
/// size follows as a `resize` as soon as the terminal is laid out.
const TerminalGrid fallbackGrid = (cols: 80, rows: 24);

/// JetBrains Mono, bundled (spec §9.1); the rest of the UI uses the base's Raleway.
TerminalStyle shellxTerminalStyle(double fontSize) =>
    TerminalStyle(fontSize: fontSize, fontFamily: FontFamily.jetBrainsMono);

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

`apps/mobile/lib/features/terminal/presentation/widgets/pinch_zoom.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:shellx_mobile/core/settings/app_settings.dart';

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

- [ ] **Step 4: Run the test and the analyzer**

```bash
cd apps/mobile
flutter test test/features/terminal/terminal_metrics_test.dart
flutter analyze
```

Expected: `+7: All tests passed!`; `No issues found!`. (The whole suite: `+212`.)

- [ ] **Step 5: Commit**

```bash
git add apps/mobile
git commit -m "feat(mobile): terminal grid measurement and pinch-to-zoom"
```

---

### Task 9: User-facing error texts (spec §12), the guard's error mapping, "Lần cuối online" wording

**Gate:** plan 03 up to Task 10 is merged (`packages/shellx_client` with the overview §5.7 types).

**Files:**
- Modify: `apps/mobile/pubspec.yaml` (depends on `shellx_client`)
- Create: `apps/mobile/lib/core/architecture/error_text.dart`
- Modify: `apps/mobile/lib/core/architecture/error_factory.dart`, `apps/mobile/lib/core/core.dart`
- Create: `apps/mobile/lib/features/machines/presentation/last_seen.dart`
- Test: `apps/mobile/test/core/architecture/error_text_test.dart`, `apps/mobile/test/core/architecture/controller_test.dart`, `apps/mobile/test/features/machines/last_seen_test.dart`, `apps/mobile/test/support/fake_popup_handler.dart`

**Interfaces:**
- Consumes: `ApiException` (`status`, `code`), `PairingException(failure)`, `PairingFailure` (`shellx_core`); `AppErrorException(code, message)`, `AppErrorCode`, `MachineFailed(failure)`, `MachineConnectionException(failure)`, `MachineConnectionFailure` (`shellx_client`, overview §5.7); `S` (Task 1); the base `AppError`/`NetworkError`/`UnauthorizedError`/`UnknownError`.
- Produces: `final class ErrorText { const ErrorText(S strings); String describe(Object error); String api(ApiException); String pairing(PairingFailure); String machine(MachineConnectionFailure); String appError(AppErrorCode, String message); }` — every user-visible failure goes through it; `ErrorFactory.fromException` now titles every `AppError` with `ErrorText(S.current).describe(e)` (so `Controller.guard` toasts §12 texts); `String formatLastSeen(S strings, DateTime? lastSeen, DateTime now)`; test helper `FakePopupHandler` (records `errors`, `successes`, `infos`).

- [ ] **Step 1: Depend on `shellx_client`**

Edit `apps/mobile/pubspec.yaml` — replace:

```yaml
  shellx_core: any
```

with:

```yaml
  shellx_client: any
  shellx_core: any
```

Run from the repository root: `flutter pub get` → `Got dependencies!`.

- [ ] **Step 2: Write the failing tests**

`apps/mobile/test/support/fake_popup_handler.dart`:

```dart
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:toastification/toastification.dart';

/// Records the toasts a controller or page shows instead of drawing them.
/// Register it with `getIt.registerSingleton<PopupHandler>(FakePopupHandler())`.
class FakePopupHandler implements PopupHandler {
  final List<String> errors = [];
  final List<String> successes = [];
  final List<String> infos = [];

  @override
  void showError({
    ToastificationCallbacks callbacks = const ToastificationCallbacks(),
    ToastificationType? type,
    required String title,
    String? description,
    IconData? icon,
  }) => errors.add(title);

  @override
  void showSuccess({
    ToastificationCallbacks callbacks = const ToastificationCallbacks(),
    ToastificationType? type,
    required String title,
    String? description,
    IconData? icon,
  }) => successes.add(title);

  @override
  void showInfo({
    ToastificationCallbacks callbacks = const ToastificationCallbacks(),
    ToastificationType? type,
    required String title,
    String? description,
    IconData? icon,
  }) => infos.add(title);

  @override
  void hide() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
```

`apps/mobile/test/core/architecture/error_text_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/shared/shared.dart';

ApiException apiError(int status, String code) => ApiException(status: status, code: code, message: code);

void main() {
  // intl_utils' S reads the process-wide locale set by the last S.load, so each group loads its own.
  group('Vietnamese', () {
    late ErrorText vi;
    setUp(() async => vi = ErrorText(await S.load(const Locale('vi'))));

    test('spec §5.3/§12 pairing texts, verbatim', () {
      expect(
        vi.pairing(PairingFailure.notInAccount),
        'Máy này không thuộc tài khoản của bạn. Hãy đăng nhập cùng tài khoản trên máy tính.',
      );
      expect(
        vi.pairing(PairingFailure.invalidOrExpired),
        'Mã QR không hợp lệ hoặc đã hết hạn. Hãy tạo mã mới trên máy tính.',
      );
      expect(vi.pairing(PairingFailure.protocolUnsupported), 'Cần cập nhật app');
    });

    test('spec §12 machine connection texts', () {
      expect(vi.machine(MachineConnectionFailure.untrusted), 'Máy không còn tin cậy điện thoại này. Hãy ghép nối lại.');
      expect(vi.machine(MachineConnectionFailure.protocolUnsupported), 'Cần cập nhật app');
      expect(vi.machine(MachineConnectionFailure.agentOffline), 'Máy đang offline.');
    });

    test('spec §12 session errors; spawn_failed shows the reason', () {
      expect(vi.appError(AppErrorCode.sessionLimit, 'x'), 'Máy đã mở tối đa 10 phiên. Hãy đóng bớt phiên.');
      expect(vi.appError(AppErrorCode.sessionNotFound, 'x'), 'Phiên đã kết thúc');
      expect(vi.appError(AppErrorCode.spawnFailed, 'pwsh.exe not found'), 'Không mở được shell: pwsh.exe not found');
    });

    test('HTTP 429 always maps to "Thử lại sau ít phút."', () {
      expect(vi.api(apiError(429, 'rate_limited')), 'Thử lại sau ít phút.');
      expect(vi.api(apiError(429, 'anything')), 'Thử lại sau ít phút.');
    });

    test('account error codes of spec §10.2', () {
      expect(vi.api(apiError(401, 'invalid_credentials')), 'Email hoặc mật khẩu không đúng.');
      expect(vi.api(apiError(409, 'email_taken')), 'Email này đã được đăng ký.');
      expect(vi.api(apiError(400, 'invalid_email')), 'Email không hợp lệ.');
      expect(vi.api(apiError(400, 'disposable_email')), 'Email tạm thời không dùng được. Hãy dùng email thật.');
      expect(vi.api(apiError(400, 'weak_password')), 'Mật khẩu phải có 8–128 ký tự.');
      expect(vi.api(apiError(0, 'network')), 'Không kết nối được máy chủ. Hãy kiểm tra mạng rồi thử lại.');
      expect(vi.api(apiError(401, 'unauthorized')), 'Phiên đăng nhập đã hết hiệu lực. Hãy đăng nhập lại.');
      expect(vi.api(apiError(500, 'internal')), 'Đã có lỗi xảy ra (internal).');
    });

    test('describe dispatches on the error type', () {
      expect(vi.describe(const PairingException(PairingFailure.timeout)), 'Máy tính không phản hồi. Hãy thử lại.');
      expect(
        vi.describe(const AppErrorException(AppErrorCode.sessionLimit, 'limit')),
        'Máy đã mở tối đa 10 phiên. Hãy đóng bớt phiên.',
      );
      expect(
        vi.describe(const MachineFailed(MachineConnectionFailure.untrusted)),
        'Máy không còn tin cậy điện thoại này. Hãy ghép nối lại.',
      );
      expect(vi.describe(const MachineConnectionException(MachineConnectionFailure.agentOffline)), 'Máy đang offline.');
      expect(vi.describe(StateError('boom')), 'Đã có lỗi xảy ra (StateError).');
    });
  });

  group('English', () {
    late ErrorText en;
    setUp(() async => en = ErrorText(await S.load(const Locale('en'))));

    test('equivalent texts', () {
      expect(
        en.pairing(PairingFailure.invalidOrExpired),
        'The QR code is invalid or has expired. Create a new code on your computer.',
      );
      expect(
        en.machine(MachineConnectionFailure.untrusted),
        'This computer no longer trusts this phone. Please pair again.',
      );
      expect(en.appError(AppErrorCode.sessionNotFound, 'x'), 'Session ended');
      expect(en.api(apiError(429, 'rate_limited')), 'Try again in a few minutes.');
    });
  });
}
```

`apps/mobile/test/core/architecture/controller_test.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/shared/shared.dart';

import '../../support/fake_popup_handler.dart';

class _Probe extends Controller {}

void main() {
  late FakePopupHandler popups;
  late List<String?> logs;
  late DebugPrintCallback originalDebugPrint;

  setUp(() async {
    await S.load(const Locale('vi'));
    popups = FakePopupHandler();
    getIt.registerSingleton<PopupHandler>(popups);
    logs = [];
    originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message);
  });

  tearDown(() async {
    debugPrint = originalDebugPrint;
    await getIt.reset();
  });

  test('guard shows the spec §12 text and never logs the error itself', () async {
    await _Probe().guard(
      () async =>
          throw const ApiException(status: 401, code: 'invalid_credentials', message: 'token=abc123 password=hunter2'),
    );

    expect(popups.errors, ['Email hoặc mật khẩu không đúng.']);
    expect(logs.join('\n'), isNot(contains('hunter2')));
    expect(logs.join('\n'), isNot(contains('abc123')));
  });

  test('ErrorFactory keeps the original error for code and maps the title', () {
    final error = ErrorFactory().fromException(const ApiException(status: 429, code: 'rate_limited', message: 'slow'));
    expect(error.title, 'Thử lại sau ít phút.');
    expect(error.originalError, isA<ApiException>());
    expect(
      ErrorFactory().fromException(const ApiException(status: 0, code: 'network', message: 'x')),
      isA<NetworkError>(),
    );
    expect(ErrorFactory().fromException(StateError('boom')).title, 'Đã có lỗi xảy ra (StateError).');
  });
}
```

`apps/mobile/test/features/machines/last_seen_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/machines/presentation/last_seen.dart';
import 'package:shellx_mobile/shared/shared.dart';

void main() {
  final now = DateTime(2026, 9, 25, 12);

  test('the design wording in Vietnamese', () async {
    final vi = await S.load(const Locale('vi'));
    expect(formatLastSeen(vi, null, now), 'không rõ');
    expect(formatLastSeen(vi, now.subtract(const Duration(seconds: 30)), now), 'vừa xong');
    expect(formatLastSeen(vi, now.subtract(const Duration(minutes: 5)), now), '5 phút trước');
    expect(formatLastSeen(vi, DateTime(2026, 9, 25, 9, 12), now), 'hôm nay, 09:12');
    expect(formatLastSeen(vi, DateTime(2026, 9, 24, 18, 5), now), 'hôm qua, 18:05');
    expect(formatLastSeen(vi, DateTime(2026, 9, 23, 18, 5), now), '23/9, 18:05');
  });

  test('English; a timestamp in the future (clock skew) reads as "just now"', () async {
    final en = await S.load(const Locale('en'));
    expect(formatLastSeen(en, now.subtract(const Duration(minutes: 1)), now), '1 minute ago');
    expect(formatLastSeen(en, DateTime(2026, 9, 24, 18, 5), now), 'yesterday, 18:05');
    expect(formatLastSeen(en, DateTime(2026, 9, 23, 18, 5), now), '9/23, 18:05');
    expect(formatLastSeen(en, now.add(const Duration(minutes: 3)), now), 'just now');
  });
}
```

- [ ] **Step 3: Run them to see them fail**

Run: `cd apps/mobile && flutter test test/core/architecture test/features/machines/last_seen_test.dart`
Expected: FAIL — `ErrorText` and `formatLastSeen` are not defined; the guard still toasts "Đã có lỗi xảy ra, hãy thử lại".

- [ ] **Step 4: Implement**

`apps/mobile/lib/core/architecture/error_text.dart`:

```dart
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Turns contract exceptions and failure codes into the user-facing texts of
/// spec §12 (Vietnamese) and their English equivalents.
final class ErrorText {
  const ErrorText(this.strings);

  final S strings;

  String describe(Object error) => switch (error) {
    ApiException() => api(error),
    PairingException(:final failure) => pairing(failure),
    AppErrorException(:final code, :final message) => appError(code, message),
    MachineFailed(:final failure) => machine(failure),
    MachineConnectionException(:final failure) => machine(failure),
    _ => strings.errorUnknown(error.runtimeType.toString()),
  };

  /// HTTP 429 is recognised by status, never by code (plan 02).
  String api(ApiException error) {
    if (error.status == 429) return strings.errorRateLimited;
    return switch (error.code) {
      'network' => strings.errorNetwork,
      'unauthorized' => strings.signedOutExpired,
      'invalid_email' => strings.errorInvalidEmail,
      'disposable_email' => strings.errorDisposableEmail,
      'weak_password' => strings.errorWeakPassword,
      'email_taken' => strings.errorEmailTaken,
      'invalid_credentials' => strings.errorInvalidCredentials,
      _ => strings.errorUnknown(error.code),
    };
  }

  /// `invalidOrExpired` uses the fuller §12 text (the §5.3 text is its first sentence).
  String pairing(PairingFailure failure) => switch (failure) {
    PairingFailure.notInAccount => strings.errorNotInAccount,
    PairingFailure.invalidOrExpired => strings.errorQrInvalid,
    PairingFailure.agentOffline => strings.errorAgentOffline,
    PairingFailure.protocolUnsupported => strings.updateRequiredTitle,
    PairingFailure.timeout => strings.errorTimeout,
  };

  String machine(MachineConnectionFailure failure) => switch (failure) {
    MachineConnectionFailure.untrusted => strings.errorUntrusted,
    MachineConnectionFailure.protocolUnsupported => strings.updateRequiredTitle,
    MachineConnectionFailure.agentOffline => strings.machineOffline,
    MachineConnectionFailure.timeout => strings.errorTimeout,
  };

  String appError(AppErrorCode code, String message) => switch (code) {
    AppErrorCode.sessionLimit => strings.errorSessionLimit,
    AppErrorCode.sessionNotFound => strings.sessionEnded,
    AppErrorCode.spawnFailed => strings.errorSpawnFailed(message),
  };
}
```

`apps/mobile/lib/core/architecture/error_factory.dart` (replace the whole file):

```dart
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/architecture/error.dart';
import 'package:shellx_mobile/core/architecture/error_text.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Turns anything a guarded call throws into the [AppError] the user sees.
///
/// The title is always a spec §12 text (via [ErrorText]), never the thrown object's `toString()`:
/// API and relay failures can carry request details (overview §2).
class ErrorFactory {
  AppError fromException(Object e, {StackTrace? stackTrace}) {
    final title = ErrorText(S.current).describe(e);
    return switch (e) {
      ApiException(code: 'network') => NetworkError(title: title, originalError: e, stackTrace: stackTrace),
      ApiException(code: 'unauthorized') => UnauthorizedError(title: title, originalError: e, stackTrace: stackTrace),
      ApiException() ||
      PairingException() ||
      AppErrorException() ||
      MachineFailed() ||
      MachineConnectionException() => AppError(title: title, originalError: e, stackTrace: stackTrace),
      _ => UnknownError(title: title, originalError: e, stackTrace: stackTrace),
    };
  }
}
```

`apps/mobile/lib/core/core.dart` (replace the whole file):

```dart
export 'dependency/dependency.dart';
export 'design/app_colors.dart';
export 'design/dark_colors.dart';
export 'design/light_colors.dart';
export 'design/typography.dart';
export 'design/design_system.dart';
export 'design/theme_data_factory.dart';
export 'design/terminal_colors.dart';
export 'extensions/adaptive_theme_mode_x.dart';
export 'router/app_router.dart';
export 'architecture/error.dart';
export 'architecture/error_factory.dart';
export 'architecture/error_text.dart';
export 'architecture/controller.dart';
export 'architecture/state_signal.dart';
export 'handler/popup_handler.dart';
export 'architecture/page_domain.dart';
export 'architecture/paging_state_signal.dart';
export 'architecture/state.dart';
export 'router/app_router.gr.dart';
export 'handler/event_notifier.dart';
export 'router/app_transparent_route.dart';
export 'router/app_route_observer.dart';
// ShellX
export 'auth/account_session.dart';
export 'auth/auth_storage.dart';
export 'config/app_config.dart';
export 'platform/device_description.dart';
export 'platform/external_links.dart';
export 'platform/fresh_install.dart';
export 'platform/secure_key_value_store.dart';
export 'settings/app_settings.dart';

// 3rd party
export 'package:auto_route/auto_route.dart';
export 'package:flutter/material.dart';
export 'package:get_it/get_it.dart';
export 'package:injectable/injectable.dart';
export 'package:signals_flutter/signals_flutter.dart';
export 'package:equatable/equatable.dart';
```

`apps/mobile/lib/features/machines/presentation/last_seen.dart`:

```dart
import 'package:shellx_mobile/shared/shared.dart';

/// The `…` of "Lần cuối online: …" (spec §9.2 #2, §12) in the design's wording:
/// "vừa xong", "5 phút trước", "hôm nay, 09:12", "hôm qua, 18:05", "23/9, 18:05".
String formatLastSeen(S strings, DateTime? lastSeen, DateTime now) {
  if (lastSeen == null) return strings.lastSeenUnknown;
  final local = lastSeen.toLocal();
  final elapsed = now.difference(local);
  if (elapsed.inMinutes < 1) return strings.lastSeenJustNow;
  if (elapsed.inHours < 1) return strings.lastSeenMinutes(elapsed.inMinutes);
  final time = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  if (day == today) return strings.lastSeenToday(time);
  if (day == today.subtract(const Duration(days: 1))) return strings.lastSeenYesterday(time);
  return strings.lastSeenDate(local.day, local.month, time);
}
```

- [ ] **Step 5: Run the tests and the analyzer**

```bash
cd apps/mobile
flutter test test/core/architecture test/features/machines/last_seen_test.dart
flutter analyze
flutter test
```

Expected: `+11: All tests passed!`; `No issues found!`; `+223: All tests passed!`.

- [ ] **Step 6: Commit**

```bash
git add apps/mobile
git commit -m "feat(mobile): spec §12 error texts behind the base's guard and last-online wording"
```

---

### Task 10: Backend ports and the `shellx_client` adapter

**Gate:** plan 03 Tasks 11–14 are merged (`ClientService`, `MachineClient`, `ClientTab`, `PinnedStore`, pairing initiator). This and every later task needs them.

**Files:**
- Create: `apps/mobile/lib/core/backend/backend.dart`, `apps/mobile/lib/core/backend/client_backend.dart`
- Modify: `apps/mobile/lib/core/core.dart`
- Create: `apps/mobile/test/support/fakes.dart`
- Test: `apps/mobile/test/core/backend/client_backend_test.dart`

**Interfaces:**
- Consumes (overview §5.5/§5.7, exact): `RelayConnection({required Uri wsUri, required String? Function() token, RelaySocketConnector connector})`, `.state`, `.states`, `.reconnectNow()`; `ShellxApi.token`, `.devices()`; `PinnedStore(KeyValueStore, {required String userId})`, `.list()`; `ClientService({relay, api, deviceId, userId, identity, pinned, appVersion, deviceName, platform})`, `.start()`, `.stop()`, `.isOnline()`, `.presence`, `.pair()`, `.machine()`, `.unpair()`; `MachineClient` and `ClientTab` members; `relayWebSocketUri`, `AppConfig.relayBaseUri`, `DeviceDescription`, `AccountSession` (Task 3); the DI singletons `ShellxApi`, `KeyValueStore`, `DeviceDescription`, `PackageInfo` (Task 3).
- Produces (used by every later task):
  - `abstract interface class TabHandle { int get id; int get index; String get shell; bool get isAttached; Stream<TabEvent> get events; }`
  - `abstract interface class MachineSession { String get agentId; MachineConnectionState get state; Stream<MachineConnectionState> get states; Future<void> connect(); Future<List<SessionInfo>> listSessions(); Future<TabHandle> openSession({required int cols, required int rows}); Future<TabHandle> attach(int id, {required int cols, required int rows}); List<TabHandle> get tabs; void input(int id, Uint8List data); void resize(int id, int cols, int rows); Future<void> closeTab(int id); }`
  - `abstract interface class ShellxBackend { RelayConnectionState get relayState; Stream<RelayConnectionState> get relayStates; void reconnectNow(); Future<void> suspend(); Future<void> resume(); Future<List<RemoteDevice>> devices(); bool isOnline(String agentId); Stream<PresenceFrame> get presence; Future<List<PinnedMachine>> pinnedMachines(); Future<void> pair(PairingUri uri); MachineSession machine(String agentId); Future<void> unpair(String agentId); Future<void> dispose(); }`
  - `abstract interface class BackendFactory { Future<ShellxBackend> create(AccountSession session, NoiseKeyPair identity); }` with the production `@LazySingleton(as: BackendFactory)` `ClientBackendFactory(ShellxApi, KeyValueStore, DeviceDescription, PackageInfo)`
  - `final class ClientBackend implements ShellxBackend { static Future<ClientBackend> start({required Uri relayBaseUri, required ShellxApi api, required String userId, required String deviceId, required NoiseKeyPair identity, required KeyValueStore store, required String appVersion, required DeviceDescription device, RelaySocketConnector connector = ioRelaySocketConnector}); }`
  - Test support (`test/support/fakes.dart`): `agentA`, `agentB`, `agentDevice(...)`, `pinned(...)`, `FakeTabHandle` (`emit`), `FakeMachineSession` (scriptable connect/list/open/attach errors, `attachHook`, `reuseHandles`, records inputs/resizes/closes), `FakeBackend` (`emitRelay`, `emitPresence`, `addMachine`, records `paired`/`unpaired`/`reconnectCalls`/`suspendCalls`/`resumeCalls`/`disposed`), `FakeBackendFactory` (hands out `FakeBackend`s and records the sessions it was asked for).

Why the ports: `ClientService`, `MachineClient` and `ClientTab` are `final` classes, so tests cannot implement them; the UI depends on these interfaces and `ClientBackend` is the only place that touches `shellx_client`. Lifecycle (plan 03): `ClientService.start()` subscribes and starts the relay, `stop()` stops it, and `start()` may run again — so `suspend()` = `client.stop()`, `resume()` = `client.start()` (machines and tabs survive; `shellx_client` re-handshakes and re-attaches on reconnect), `dispose()` = `client.stop()`. The adapter never calls `relay.start()`/`stop()` itself. `BackendFactory` is what `SessionHolder` (Task 11) calls once per sign-in; it shares the app's single `KeyValueStore` and `ShellxApi` from DI.

- [ ] **Step 1: Write the test fakes**

`apps/mobile/test/support/fakes.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;

const String agentA = '11111111-1111-4111-8111-111111111111';
const String agentB = '22222222-2222-4222-8222-222222222222';

RemoteDevice agentDevice(
  String id,
  String name, {
  bool online = true,
  DateTime? lastSeenAt,
  DevicePlatform platform = DevicePlatform.macos,
}) => RemoteDevice(
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
  final StreamController<MachineConnectionState> _states = StreamController<MachineConnectionState>.broadcast(
    sync: true,
  );
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
  final StreamController<RelayConnectionState> _relay = StreamController<RelayConnectionState>.broadcast(sync: true);
  final StreamController<PresenceFrame> _presence = StreamController<PresenceFrame>.broadcast(sync: true);
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

  FakeMachineSession addMachine(String agentId) => machines.putIfAbsent(agentId, () => FakeMachineSession(agentId));

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
  MachineSession machine(String agentId) => machines[agentId] ?? (throw StateError('not pinned: $agentId'));

  @override
  Future<void> unpair(String agentId) async {
    unpaired.add(agentId);
    pinnedList = pinnedList.where((m) => m.agentId != agentId).toList();
    machines.remove(agentId);
  }

  @override
  Future<void> dispose() async => disposed = true;
}

/// Hands out a new [FakeBackend] per sign-in and records what it was asked for.
class FakeBackendFactory implements BackendFactory {
  FakeBackendFactory([FakeBackend Function()? build]) : _build = build ?? FakeBackend.new;

  final FakeBackend Function() _build;
  final List<FakeBackend> backends = [];
  final List<AccountSession> sessions = [];
  final List<NoiseKeyPair> identities = [];

  @override
  Future<ShellxBackend> create(AccountSession session, NoiseKeyPair identity) async {
    sessions.add(session);
    identities.add(identity);
    final backend = _build();
    backends.add(backend);
    return backend;
  }
}
```

- [ ] **Step 2: Write the failing test**

`apps/mobile/test/core/backend/client_backend_test.dart` (uses the real `shellx_core`/`shellx_client` classes; the socket connector fails so no network is touched):

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/backend/client_backend.dart';
import 'package:shellx_mobile/core/platform/device_description.dart';

import '../../support/fakes.dart';

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

- [ ] **Step 3: Run it to see it fail**

Run: `cd apps/mobile && flutter test test/core/backend`
Expected: FAIL — `Error when reading 'lib/core/backend/client_backend.dart': No such file or directory` (and `TabHandle`/`MachineSession`/`ShellxBackend` are not defined for `fakes.dart`).

- [ ] **Step 4: Implement**

`apps/mobile/lib/core/backend/backend.dart`:

```dart
import 'dart:typed_data';

import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/auth/account_session.dart';

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

/// Builds the backend of a signed-in account; `ClientBackendFactory` in production, a fake in tests.
abstract interface class BackendFactory {
  Future<ShellxBackend> create(AccountSession session, NoiseKeyPair identity);
}
```

`apps/mobile/lib/core/backend/client_backend.dart`:

```dart
import 'dart:typed_data';

import 'package:injectable/injectable.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/auth/account_session.dart';
import 'package:shellx_mobile/core/backend/backend.dart';
import 'package:shellx_mobile/core/config/app_config.dart';
import 'package:shellx_mobile/core/platform/device_description.dart';

/// Production [BackendFactory]: one [ClientBackend] per sign-in, sharing the app's single
/// [KeyValueStore] and [ShellxApi].
@LazySingleton(as: BackendFactory)
final class ClientBackendFactory implements BackendFactory {
  ClientBackendFactory(this._api, this._store, this._device, this._packageInfo);

  final ShellxApi _api;
  final KeyValueStore _store;
  final DeviceDescription _device;
  final PackageInfo _packageInfo;

  @override
  Future<ShellxBackend> create(AccountSession session, NoiseKeyPair identity) => ClientBackend.start(
    relayBaseUri: AppConfig.relayBaseUri,
    api: _api,
    userId: session.userId,
    deviceId: session.deviceId,
    identity: identity,
    store: _store,
    appVersion: _packageInfo.version,
    device: _device,
  );
}

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

`apps/mobile/lib/core/core.dart` (replace the whole file):

```dart
export 'dependency/dependency.dart';
export 'design/app_colors.dart';
export 'design/dark_colors.dart';
export 'design/light_colors.dart';
export 'design/typography.dart';
export 'design/design_system.dart';
export 'design/theme_data_factory.dart';
export 'design/terminal_colors.dart';
export 'extensions/adaptive_theme_mode_x.dart';
export 'router/app_router.dart';
export 'architecture/error.dart';
export 'architecture/error_factory.dart';
export 'architecture/error_text.dart';
export 'architecture/controller.dart';
export 'architecture/state_signal.dart';
export 'handler/popup_handler.dart';
export 'architecture/page_domain.dart';
export 'architecture/paging_state_signal.dart';
export 'architecture/state.dart';
export 'router/app_router.gr.dart';
export 'handler/event_notifier.dart';
export 'router/app_transparent_route.dart';
export 'router/app_route_observer.dart';
// ShellX
export 'auth/account_session.dart';
export 'auth/auth_storage.dart';
export 'backend/backend.dart';
export 'backend/client_backend.dart';
export 'config/app_config.dart';
export 'platform/device_description.dart';
export 'platform/external_links.dart';
export 'platform/fresh_install.dart';
export 'platform/secure_key_value_store.dart';
export 'settings/app_settings.dart';

// 3rd party
export 'package:auto_route/auto_route.dart';
export 'package:flutter/material.dart';
export 'package:get_it/get_it.dart';
export 'package:injectable/injectable.dart';
export 'package:signals_flutter/signals_flutter.dart';
export 'package:equatable/equatable.dart';
```

- [ ] **Step 5: Generate, run the test, analyze**

```bash
cd apps/mobile
dart run build_runner build
flutter test test/core/backend
flutter analyze
flutter test
```

Expected: `+1: All tests passed!`; `No issues found!`; `+224: All tests passed!`.

- [ ] **Step 6: Commit**

```bash
git add apps/mobile
git commit -m "feat(mobile): backend ports and the shellx_client adapter"
```

---

### Task 11: Account lifecycle — version gate, sign in/up, sign out, 4002, 4001, background, delete account

This replaces the base's `SessionHolder`/`AuthStorage` (which were built around an access + refresh token pair) with one for ShellX: one opaque device token plus `user_id`, `device_id` and the email, all in the `KeyValueStore` (Task 3). It keeps the base's pattern — the holder exposes signals and announces sign-in/sign-out on `AuthEventNotifier`; Task 19's `SessionEnforcer` turns those events into navigation.

**Files:**
- Create: `apps/mobile/lib/core/auth/auth_event.dart`, `apps/mobile/lib/core/auth/session_holder.dart`, `apps/mobile/lib/core/version/version_gate.dart`
- Modify: `apps/mobile/lib/core/core.dart`
- Create: `apps/mobile/test/support/fake_relay_http.dart`
- Test: `apps/mobile/test/core/auth/session_holder_test.dart`, `apps/mobile/test/core/version/version_gate_test.dart`

**Interfaces:**
- Consumes: `ShellxApi` (`version`, `login`, `register`, `logout`, `deleteAccount`, `token`), `compareVersions`, `DeviceInfo`, `DeviceKind`, `NoiseKeyPair`, `DeviceIdentity.loadOrCreate`, `ApiException`, `RelayConnectionState` (overview §5.2, §5.5); `ShellxBackend`, `BackendFactory` (Task 10); `AuthStorage`, `AccountSession`, `DeviceDescription` (Task 3); the base `EventNotifier`.
- Produces:
  - `enum SignOutReason { loggedOut, revoked, accountDeleted }`, `sealed class AuthEvent` with `SignedInEvent()` and `SignedOutEvent(SignOutReason reason)`, `AuthEventKeys.sessionEnforcer`, `@lazySingleton class AuthEventNotifier extends EventNotifier<AuthEvent>`
  - `abstract class SessionHolder { ReadonlySignal<AccountSession?> get session; ReadonlySignal<bool> get isAuthenticated; ReadonlySignal<ShellxBackend?> get backend; ShellxBackend get requireBackend; ReadonlySignal<SignOutReason?> get signOutReason; String? get lastEmail; String get appVersion; Future<void> restore(); Future<void> login(String email, String password); Future<void> register(String email, String password); Future<void> logout(); Future<void> deleteAccount(String password); Future<void> reconnectReplaced(); void onBackground(); void onForeground(); }` with `@LazySingleton(as: SessionHolder)` `SessionHolderImpl({api, storage, store, device, packageInfo, backends, events})`
  - `@lazySingleton class VersionGate { VersionGate(ShellxApi, PackageInfo); ReadonlySignal<String?> get requiredVersion; Future<void> check(); }`
  - Test support: `FakeRelayHttp` (scripted `/v1/version`, `/v1/auth/*`, `DELETE /v1/account`) with `testUserId`, `testDeviceId`.

Behaviour pinned by the tests: `/v1/version` newer than the app → `requiredVersion` set (unreachable relay does not block); login/register trim and lower-case the email and send the phone's `DeviceInfo`; logout deletes **only** the token (device key and `pinned_machines_<userId>` stay, spec §5.2) and works offline; `revoked` (4002 or a 401 upgrade) → token deleted, `SignedOutEvent(revoked)`, the email kept for the login form; `replaced` (4001) is never reconnected automatically — `reconnectReplaced()` restarts the same backend (`suspend` + `resume`) on user request, keeping machines and tabs; `onBackground()` suspends the backend (spec §12: retry only in the foreground; iOS drops the socket anyway) unless it is replaced/revoked/stopped; `onForeground()` resumes a suspended backend, or calls `reconnectNow()` for a `disconnected` relay; `deleteAccount` forgets token + ids + email + device key + this user's pins and ignores the 4002 that accompanies it. `StreamSubscription.cancel()` is deliberately not awaited: cancellation is immediate and awaiting its root-zone future stalls under `fake_async` in widget tests.

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
          jsonEncode({
            'error': {'code': 'invalid_credentials', 'message': 'wrong password'},
          }),
          401,
        );
      }
      return http.Response('', 204);
    }
    if (path == '/v1/auth/logout') {
      if (logoutOffline) throw http.ClientException('offline');
      return http.Response('', 204);
    }
    return http.Response(
      jsonEncode({
        'error': {'code': 'not_found', 'message': path},
      }),
      404,
    );
  });

  http.Request lastTo(String path) => requests.lastWhere((r) => r.url.path == path);
}
```

- [ ] **Step 2: Write the failing tests**

`apps/mobile/test/core/auth/session_holder_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;

import '../../support/fake_relay_http.dart';
import '../../support/fakes.dart';

PackageInfo packageInfo(String version) =>
    PackageInfo(appName: 'ShellX', packageName: 'pro.shellx.mobile', version: version, buildNumber: '1');

void main() {
  late FakeRelayHttp relay;
  late InMemoryKeyValueStore store;
  late ShellxApi api;
  late FakeBackendFactory backends;
  late AuthEventNotifier notifier;
  late List<AuthEvent> events;

  SessionHolderImpl holder() => SessionHolderImpl(
    api: api,
    storage: AuthStorageImpl(store),
    store: store,
    device: const DeviceDescription(name: 'iPhone 15', platform: DevicePlatform.ios),
    packageInfo: packageInfo('1.0.0'),
    backends: backends,
    events: notifier,
  );

  setUp(() {
    relay = FakeRelayHttp();
    store = InMemoryKeyValueStore();
    api = ShellxApi(baseUri: Uri.parse('http://127.0.0.1:8787'), httpClient: relay.client);
    backends = FakeBackendFactory();
    notifier = AuthEventNotifier();
    events = [];
    notifier.addListener('test', events.add);
  });

  Future<void> saveSession() => AuthStorageImpl(store).save(
    const AccountSession(userId: testUserId, deviceId: testDeviceId, token: 'saved', email: 'a@b.co'),
  );

  test('restores a saved session and starts its backend, without an event', () async {
    await saveSession();
    final session = holder();
    await session.restore();
    expect(session.isAuthenticated.value, isTrue);
    expect(session.requireBackend, same(backends.backends.single));
    expect(api.token, 'saved');
    expect(backends.sessions.single.userId, testUserId);
    expect(events, isEmpty);
  });

  test('nothing saved: stays signed out and remembers no email', () async {
    final session = holder();
    await session.restore();
    expect(session.isAuthenticated.value, isFalse);
    expect(session.backend.value, isNull);
    expect(() => session.requireBackend, throwsStateError);
  });

  test('login normalises the email and sends the mobile device info', () async {
    final session = holder();
    await session.restore();
    await session.login('  Me@Example.COM ', 'correct horse');

    final body = jsonDecode(relay.lastTo('/v1/auth/login').body) as Map<String, Object?>;
    expect(body['email'], 'me@example.com');
    final device = body['device'] as Map<String, Object?>;
    expect(device['kind'], 'mobile');
    expect(device['platform'], 'ios');
    expect(device['name'], 'iPhone 15');
    final identity = await DeviceIdentity.loadOrCreate(store);
    expect(device['public_key'], base64UrlNoPad(identity.publicKey));
    expect(backends.identities.single.publicKey, identity.publicKey);

    expect(session.isAuthenticated.value, isTrue);
    expect(events.single, isA<SignedInEvent>());
    final saved = await AuthStorageImpl(store).load();
    expect(saved?.token, 'token-1');
    expect(saved?.email, 'me@example.com');
  });

  test('register uses /v1/auth/register', () async {
    final session = holder();
    await session.register('new@example.com', 'long enough');
    expect(relay.requests.map((r) => r.url.path), contains('/v1/auth/register'));
    expect(session.isAuthenticated.value, isTrue);
  });

  test('a rejected login throws ApiException and stays signed out', () async {
    relay.loginError = {'status': 401, 'code': 'invalid_credentials', 'message': 'no'};
    final session = holder();
    await expectLater(
      session.login('a@b.co', 'wrong password'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'invalid_credentials')),
    );
    expect(session.isAuthenticated.value, isFalse);
    expect(await AuthStorageImpl(store).load(), isNull);
    expect(events, isEmpty);
  });

  test('logout deletes only the token (spec §5.2)', () async {
    await saveSession();
    await store.write(DeviceIdentity.storageKey, base64UrlNoPad((await NoiseKeyPair.generate()).privateKey));
    final key = await store.read(DeviceIdentity.storageKey);
    await store.write('pinned_machines_$testUserId', '[]');
    final session = holder();
    await session.restore();

    await session.logout();

    expect(relay.lastTo('/v1/auth/logout').headers['authorization'], 'Bearer saved');
    expect(backends.backends.single.disposed, isTrue);
    expect(await store.read(AuthStorage.tokenKey), isNull);
    expect(await store.read(DeviceIdentity.storageKey), key);
    expect(await store.read('pinned_machines_$testUserId'), '[]');
    expect(await store.read(AuthStorage.userIdKey), testUserId);
    expect(api.token, isNull);
    expect(session.isAuthenticated.value, isFalse);
    expect(session.lastEmail, 'a@b.co');
    expect(session.signOutReason.value, SignOutReason.loggedOut);
    expect((events.single as SignedOutEvent).reason, SignOutReason.loggedOut);
  });

  test('logout still signs out locally when the relay is unreachable', () async {
    await saveSession();
    relay.logoutOffline = true;
    final session = holder();
    await session.restore();
    await session.logout();
    expect(session.isAuthenticated.value, isFalse);
    expect(await store.read(AuthStorage.tokenKey), isNull);
  });

  test('close code 4002 (revoked) deletes the token and signs out (spec §12)', () async {
    await saveSession();
    final session = holder();
    await session.restore();

    backends.backends.single.emitRelay(RelayConnectionState.revoked);
    await pumpEventQueue();

    expect(session.isAuthenticated.value, isFalse);
    expect(session.signOutReason.value, SignOutReason.revoked);
    expect(await store.read(AuthStorage.tokenKey), isNull);
    expect(relay.requests.where((r) => r.url.path == '/v1/auth/logout'), isEmpty);
    expect((events.single as SignedOutEvent).reason, SignOutReason.revoked);
  });

  test('reconnectReplaced restarts the same backend after 4001', () async {
    await saveSession();
    final session = holder();
    await session.restore();
    final backend = backends.backends.single;
    backend.emitRelay(RelayConnectionState.replaced);

    await session.reconnectReplaced();

    expect(backends.backends, hasLength(1));
    expect(backend.suspendCalls, 1);
    expect(backend.resumeCalls, 1);
    expect(backend.relayState, RelayConnectionState.connected);
  });

  test('background suspends the relay, foreground resumes it (spec §9.4, §12)', () async {
    await saveSession();
    final session = holder();
    await session.restore();
    final backend = backends.backends.single;

    session.onBackground();
    session.onBackground();
    expect(backend.suspendCalls, 1);

    session.onForeground();
    session.onForeground();
    expect(backend.resumeCalls, 1);
    expect(backend.reconnectCalls, 0);
  });

  test('a replaced (4001) connection is never resumed automatically', () async {
    await saveSession();
    final session = holder();
    await session.restore();
    final backend = backends.backends.single;
    backend.emitRelay(RelayConnectionState.replaced);

    session.onBackground();
    session.onForeground();

    expect(backend.suspendCalls, 0);
    expect(backend.resumeCalls, 0);
    expect(backend.reconnectCalls, 0);
  });

  test('foreground without a background skips the backoff of a disconnected relay', () async {
    await saveSession();
    final session = holder();
    await session.restore();
    final backend = backends.backends.single;

    backend.relayStateValue = RelayConnectionState.disconnected;
    session.onForeground();
    backend.relayStateValue = RelayConnectionState.connected;
    session.onForeground();

    expect(backend.reconnectCalls, 1);
  });

  group('deleteAccount', () {
    test('wrong password throws invalid_credentials and keeps the session', () async {
      await saveSession();
      final session = holder();
      await session.restore();

      await expectLater(
        session.deleteAccount('nope'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'invalid_credentials')),
      );
      expect(session.isAuthenticated.value, isTrue);
      expect(backends.backends.single.disposed, isFalse);
      expect(await store.read(AuthStorage.tokenKey), 'saved');
    });

    test("success forgets token, device key and this user's pins only", () async {
      await saveSession();
      await store.write(DeviceIdentity.storageKey, 'private-key');
      await store.write('pinned_machines_$testUserId', '[]');
      await store.write('pinned_machines_other-user', '[]');
      final session = holder();
      await session.restore();

      await session.deleteAccount('correct horse');

      final request = relay.lastTo('/v1/account');
      expect(request.method, 'DELETE');
      expect(request.headers['authorization'], 'Bearer saved');
      expect(backends.backends.single.disposed, isTrue);
      for (final key in [
        AuthStorage.tokenKey,
        AuthStorage.userIdKey,
        AuthStorage.deviceIdKey,
        AuthStorage.emailKey,
        DeviceIdentity.storageKey,
        'pinned_machines_$testUserId',
      ]) {
        expect(await store.read(key), isNull, reason: key);
      }
      expect(await store.read('pinned_machines_other-user'), '[]');
      expect(api.token, isNull);
      expect(session.isAuthenticated.value, isFalse);
      expect(session.signOutReason.value, SignOutReason.accountDeleted);
      expect((events.single as SignedOutEvent).reason, SignOutReason.accountDeleted);
    });

    test('the 4002 close that accompanies the deletion is not treated as a revocation', () async {
      await saveSession();
      final session = holder();
      await session.restore();
      final backend = backends.backends.single;

      final deletion = session.deleteAccount('correct horse');
      backend.emitRelay(RelayConnectionState.revoked);
      await deletion;
      await pumpEventQueue();

      expect(session.signOutReason.value, SignOutReason.accountDeleted);
      expect(events.whereType<SignedOutEvent>().map((e) => e.reason), [SignOutReason.accountDeleted]);
    });
  });
}
```

`apps/mobile/test/core/version/version_gate_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;

import '../../support/fake_relay_http.dart';

void main() {
  late FakeRelayHttp relay;

  VersionGate gate(String appVersion) => VersionGate(
    ShellxApi(baseUri: Uri.parse('http://127.0.0.1:8787'), httpClient: relay.client),
    PackageInfo(appName: 'ShellX', packageName: 'pro.shellx.mobile', version: appVersion, buildNumber: '1'),
  );

  setUp(() => relay = FakeRelayHttp());

  test('blocks the app when older than min_mobile (spec §14)', () async {
    relay.minMobile = '1.2.0';
    final old = gate('1.1.9');
    await old.check();
    expect(old.requiredVersion.value, '1.2.0');

    final current = gate('1.2.0');
    await current.check();
    expect(current.requiredVersion.value, isNull);
  });

  test('an unreachable /v1/version does not block the app', () async {
    relay.versionOffline = true;
    final offline = gate('1.0.0');
    await offline.check();
    expect(offline.requiredVersion.value, isNull);
  });
}
```

- [ ] **Step 3: Run them to see them fail**

Run: `cd apps/mobile && flutter test test/core/auth/session_holder_test.dart test/core/version`
Expected: FAIL — `Error when reading 'lib/core/auth/session_holder.dart': No such file or directory` (and the same for `auth_event.dart`, `version_gate.dart`).

- [ ] **Step 4: Implement**

`apps/mobile/lib/core/auth/auth_event.dart`:

```dart
import 'package:shellx_mobile/core/core.dart';

/// Why the app went back to the login screen; the login page explains the last two.
enum SignOutReason { loggedOut, revoked, accountDeleted }

// Events
sealed class AuthEvent {
  const AuthEvent();
}

/// A login or registration succeeded (not emitted when a saved session is restored at launch).
final class SignedInEvent extends AuthEvent {
  const SignedInEvent();
}

final class SignedOutEvent extends AuthEvent {
  const SignedOutEvent(this.reason);
  final SignOutReason reason;
}

// Event keys (constants to avoid magic strings)
class AuthEventKeys {
  static const sessionEnforcer = 'session_enforcer';
}

// Event Notifier
@lazySingleton
class AuthEventNotifier extends EventNotifier<AuthEvent> {}
```

`apps/mobile/lib/core/auth/session_holder.dart`:

```dart
import 'dart:async';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';

/// The signed-in account and its running backend (spec §5.2, §9.4, §12).
abstract class SessionHolder {
  ReadonlySignal<AccountSession?> get session;
  ReadonlySignal<bool> get isAuthenticated;

  /// The `shellx_core` + `shellx_client` stack of the signed-in account; null when signed out.
  ReadonlySignal<ShellxBackend?> get backend;

  /// [backend] of the signed-in account; throws [StateError] when signed out.
  ShellxBackend get requireBackend;

  /// Why the last sign-out happened; null after a successful sign-in.
  ReadonlySignal<SignOutReason?> get signOutReason;

  /// The email of the last account on this phone, to prefill the login form.
  String? get lastEmail;

  String get appVersion;

  /// Loads the saved session and starts its backend. Emits no event: the first route is guarded.
  Future<void> restore();

  /// Throws [ApiException] (e.g. `invalid_credentials`, HTTP 429).
  Future<void> login(String email, String password);

  /// Throws [ApiException] (e.g. `email_taken`, `disposable_email`).
  Future<void> register(String email, String password);

  Future<void> logout();

  /// Throws [ApiException] (`invalid_credentials` for a wrong password) and stays signed in.
  Future<void> deleteAccount(String password);

  /// Takes the connection back after close code 4001 (spec §12: never automatic).
  Future<void> reconnectReplaced();

  void onBackground();
  void onForeground();
}

@LazySingleton(as: SessionHolder)
class SessionHolderImpl implements SessionHolder {
  SessionHolderImpl({
    required ShellxApi api,
    required AuthStorage storage,
    required KeyValueStore store,
    required DeviceDescription device,
    required PackageInfo packageInfo,
    required BackendFactory backends,
    required AuthEventNotifier events,
  }) : _api = api,
       _storage = storage,
       _store = store,
       _device = device,
       _appVersion = packageInfo.version,
       _backends = backends,
       _events = events;

  final ShellxApi _api;
  final AuthStorage _storage;
  final KeyValueStore _store;
  final DeviceDescription _device;
  final String _appVersion;
  final BackendFactory _backends;
  final AuthEventNotifier _events;
  final Signal<AccountSession?> _session = signal(null);
  final Signal<ShellxBackend?> _backend = signal(null);
  final Signal<SignOutReason?> _signOutReason = signal(null);
  late final Computed<bool> _authenticated = computed(() => _session.value != null);
  StreamSubscription<RelayConnectionState>? _relaySubscription;
  String? _lastEmail;
  bool _deletingAccount = false;
  bool _suspended = false;

  @override
  ReadonlySignal<AccountSession?> get session => _session;

  @override
  ReadonlySignal<bool> get isAuthenticated => _authenticated;

  @override
  ReadonlySignal<ShellxBackend?> get backend => _backend;

  @override
  ShellxBackend get requireBackend => _backend.peek() ?? (throw StateError('Not signed in'));

  @override
  ReadonlySignal<SignOutReason?> get signOutReason => _signOutReason;

  @override
  String? get lastEmail => _lastEmail;

  @override
  String get appVersion => _appVersion;

  @override
  Future<void> restore() async {
    _lastEmail = await _storage.lastEmail();
    final saved = await _storage.load();
    if (saved == null) return;
    await _enter(saved, await DeviceIdentity.loadOrCreate(_store));
  }

  @override
  Future<void> login(String email, String password) => _authenticate(email, password, register: false);

  @override
  Future<void> register(String email, String password) => _authenticate(email, password, register: true);

  Future<void> _authenticate(String email, String password, {required bool register}) async {
    final identity = await DeviceIdentity.loadOrCreate(_store);
    final device = DeviceInfo(
      kind: DeviceKind.mobile,
      name: _device.name,
      platform: _device.platform,
      publicKey: identity.publicKey,
    );
    // Spec §5.2: trimmed and lower-cased so one account has one address.
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
    await _storage.save(session);
    await _enter(session, identity);
    _events.notifyAll(const SignedInEvent());
  }

  Future<void> _enter(AccountSession session, NoiseKeyPair identity) async {
    _api.token = session.token;
    _suspended = false;
    final backend = await _backends.create(session, identity);
    _relaySubscription = backend.relayStates.listen((state) {
      // Deleting the account closes every socket with 4002; that is not a revocation.
      if (state == RelayConnectionState.revoked && !_deletingAccount) {
        unawaited(_signOut(SignOutReason.revoked));
      }
    });
    batch(() {
      _session.value = session;
      _backend.value = backend;
      _signOutReason.value = null;
    });
  }

  Future<void> _teardown(ShellxBackend backend) async {
    // Cancelling takes effect immediately; its future only reports cleanup.
    unawaited(_relaySubscription?.cancel());
    _relaySubscription = null;
    await backend.dispose();
  }

  @override
  Future<void> logout() => _signOut(SignOutReason.loggedOut);

  Future<void> _signOut(SignOutReason reason) async {
    final session = _session.peek();
    final backend = _backend.peek();
    if (session == null || backend == null) return;
    await _teardown(backend);
    if (reason == SignOutReason.loggedOut) {
      try {
        await _api.logout();
      } on ApiException {
        // Offline: the token is still deleted locally below.
      }
    }
    await _storage.deleteToken();
    _api.token = null;
    _lastEmail = session.email;
    _cleared(reason);
  }

  void _cleared(SignOutReason reason) {
    batch(() {
      _session.value = null;
      _backend.value = null;
      _signOutReason.value = reason;
    });
    _events.notifyAll(SignedOutEvent(reason));
  }

  /// Spec §5.2 (App Store 5.1.1(v)): `DELETE /v1/account` with the password,
  /// then forget the token, the device key and this user's pinned machines.
  @override
  Future<void> deleteAccount(String password) async {
    final session = _session.peek();
    final backend = _backend.peek();
    if (session == null || backend == null) return;
    _deletingAccount = true;
    try {
      await _api.deleteAccount(password);
      await _teardown(backend);
      await _storage.forgetAccount(session.userId);
      _api.token = null;
      _lastEmail = null;
      _cleared(SignOutReason.accountDeleted);
    } finally {
      _deletingAccount = false;
    }
  }

  /// Restarting the same backend keeps every machine and tab (`RelayConnection.start()` is
  /// allowed after `replaced`).
  @override
  Future<void> reconnectReplaced() async {
    final backend = _backend.peek();
    if (backend == null) return;
    await backend.suspend();
    await backend.resume();
  }

  /// App went to the background: stop retrying (spec §12 "mobile thử khi ở
  /// foreground"); iOS would cut the socket anyway (spec §9.4).
  @override
  void onBackground() {
    final backend = _backend.peek();
    if (backend == null || _suspended) return;
    switch (backend.relayState) {
      case RelayConnectionState.replaced:
      case RelayConnectionState.revoked:
      case RelayConnectionState.stopped:
        return; // Never reconnect these automatically.
      case RelayConnectionState.disconnected:
      case RelayConnectionState.connecting:
      case RelayConnectionState.connected:
        _suspended = true;
        unawaited(backend.suspend());
    }
  }

  /// App back in the foreground: reconnect right away (spec §9.4, §12).
  @override
  void onForeground() {
    final backend = _backend.peek();
    if (backend == null) return;
    if (_suspended) {
      _suspended = false;
      unawaited(backend.resume());
    } else if (backend.relayState == RelayConnectionState.disconnected) {
      backend.reconnectNow();
    }
  }
}
```

`apps/mobile/lib/core/version/version_gate.dart`:

```dart
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';

/// Spec §12/§14: the app is blocked when it is older than `min_mobile` of `GET /v1/version`.
@lazySingleton
class VersionGate {
  VersionGate(this._api, PackageInfo packageInfo) : _appVersion = packageInfo.version;

  final ShellxApi _api;
  final String _appVersion;
  final Signal<String?> _requiredVersion = signal(null);

  /// `min_mobile` when this app is too old, else null.
  ReadonlySignal<String?> get requiredVersion => _requiredVersion;

  /// Runs on every launch. An unreachable relay does not block the app.
  Future<void> check() async {
    try {
      final info = await _api.version();
      _requiredVersion.value = compareVersions(_appVersion, info.minMobile) < 0 ? info.minMobile : null;
    } on ApiException {
      // Offline: the next launch checks again.
    }
  }
}
```

`apps/mobile/lib/core/core.dart` (replace the whole file):

```dart
export 'dependency/dependency.dart';
export 'design/app_colors.dart';
export 'design/dark_colors.dart';
export 'design/light_colors.dart';
export 'design/typography.dart';
export 'design/design_system.dart';
export 'design/theme_data_factory.dart';
export 'design/terminal_colors.dart';
export 'extensions/adaptive_theme_mode_x.dart';
export 'router/app_router.dart';
export 'architecture/error.dart';
export 'architecture/error_factory.dart';
export 'architecture/error_text.dart';
export 'architecture/controller.dart';
export 'architecture/state_signal.dart';
export 'handler/popup_handler.dart';
export 'architecture/page_domain.dart';
export 'architecture/paging_state_signal.dart';
export 'architecture/state.dart';
export 'router/app_router.gr.dart';
export 'handler/event_notifier.dart';
export 'router/app_transparent_route.dart';
export 'router/app_route_observer.dart';
// ShellX
export 'auth/account_session.dart';
export 'auth/auth_event.dart';
export 'auth/auth_storage.dart';
export 'auth/session_holder.dart';
export 'backend/backend.dart';
export 'backend/client_backend.dart';
export 'config/app_config.dart';
export 'platform/device_description.dart';
export 'platform/external_links.dart';
export 'platform/fresh_install.dart';
export 'platform/secure_key_value_store.dart';
export 'settings/app_settings.dart';
export 'version/version_gate.dart';

// 3rd party
export 'package:auto_route/auto_route.dart';
export 'package:flutter/material.dart';
export 'package:get_it/get_it.dart';
export 'package:injectable/injectable.dart';
export 'package:signals_flutter/signals_flutter.dart';
export 'package:equatable/equatable.dart';
```

- [ ] **Step 5: Generate, run the tests, analyze**

```bash
cd apps/mobile
dart run build_runner build
flutter test test/core/auth/session_holder_test.dart test/core/version
flutter analyze
flutter test
```

Expected: `+17: All tests passed!`; `No issues found!`; `+241: All tests passed!`.

- [ ] **Step 6: Commit**

```bash
git add apps/mobile
git commit -m "feat(mobile): session holder for sign-in, sign-out, 4001/4002, background and account deletion"
```

---

### Task 12: `TerminalTabController` — bind a tab's events to an xterm terminal

**Files:**
- Create: `apps/mobile/lib/features/terminal/presentation/controllers/terminal_tab_controller.dart`
- Test: `apps/mobile/test/features/terminal/terminal_tab_controller_test.dart`

**Interfaces:**
- Consumes: `TabHandle`, `MachineSession` (Task 10); `TabEvent` subclasses `TabOutput(text)`, `TabReset()`, `TabExited(exitCode)`, `TabDetached(reason)`, `TabError(code, message)`, `AppErrorException`, `DetachReason`, `AppErrorCode`, `SessionInfo` (`shellx_client`); `ShellxTerminal`, `ModifierSource` (Tasks 6–7); `TerminalController` (`package:xterm/xterm.dart`); the base `Controller`.
- Produces:
  - `enum TabNotice { exited, sessionEnded, takenOver, closedByHost, failed }`, `final class TabBanner { const TabBanner(TabNotice notice, {int? exitCode, AppErrorCode? errorCode, String? detail}); }`
  - `class TerminalTabController extends Controller { TerminalTabController({required MachineSession machine, required TabHandle handle, required ModifierSource modifiers, required int cols, required int rows, Duration resizeDebounce = const Duration(milliseconds: 150)}); TerminalTabController.ended({required MachineSession machine, required SessionInfo session, required ModifierSource modifiers, Duration resizeDebounce}); final int id; final TerminalController selection; ReadonlySignal<ShellxTerminal> get terminal; ReadonlySignal<TabBanner?> get banner; ReadonlySignal<bool> get isLive; ReadonlySignal<String> get title; Future<void> reattach(); void dispose(); }`

Event mapping: `TabOutput` → `terminal.write`; `TabReset` → a fresh `ShellxTerminal` of the same size in the `terminal` signal (xterm has no RIS); `TabExited` → banner `exited` with the exit code (kept `closedByHost` when that came first) — the output stays readable (design: "Nội dung ở trên vẫn đọc và copy được"); `TabDetached(takenOver)` → banner with "Gắn lại" (`reattach()` keeps the screen and the subscription — `shellx_client` re-attaches the same tab with `last_seq = received` and its catch-up output must not be dropped); `TabDetached(closedByHost)`; `TabError(sessionNotFound)` → "Phiên đã kết thúc" (Review Focus 1/overview RF 3); other `TabError` → reason in the tab (spawn_failed, spec §12). Input/resize only while live; resizes debounced 150 ms, deduplicated, never below 1×1 (Review Focus 2/overview RF 4). Title: OSC 0/2, else `"<shell> <index>"` (spec §7).

- [ ] **Step 1: Write the failing test**

`apps/mobile/test/features/terminal/terminal_tab_controller_test.dart`:

```dart
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' show effect;
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_tab_controller.dart';

import '../../support/fakes.dart';

void main() {
  late FakeMachineSession machine;
  late FakeTabHandle handle;
  late ExtraKeysController keys;
  late TerminalTabController tab;

  String screen() => tab.terminal.value.buffer.getText().trim();

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

    tab.terminal.value.textInput('ls\n');
    expect(utf8.decode(machine.inputs.single.data), 'ls\r');
    expect(machine.inputs.single.id, handle.id);
  });

  test('title falls back to "<shell> <index>", OSC title wins', () {
    expect(tab.title.value, 'zsh 1');
    handle.emit(const TabOutput('\x1b]2;vim notes.md\x07'));
    expect(tab.title.value, 'vim notes.md');
  });

  test('session.reset swaps in a clean terminal of the same size', () {
    tab.terminal.value.resize(100, 30);
    handle.emit(const TabOutput('stale output'));
    final before = tab.terminal.value;
    var swaps = -1; // the effect runs once right away
    final stop = effect(() {
      tab.terminal.value;
      swaps++;
    });
    addTearDown(stop);

    handle.emit(const TabReset());

    expect(tab.terminal.value, isNot(same(before)));
    expect(screen(), isEmpty);
    expect(tab.terminal.value.viewWidth, 100);
    expect(tab.terminal.value.viewHeight, 30);
    expect(swaps, 1);
    handle.emit(const TabOutput('fresh'));
    expect(screen(), 'fresh');
  });

  test('resizes are debounced and deduplicated', () {
    fakeAsync((async) {
      tab.terminal.value.resize(90, 30);
      tab.terminal.value.resize(100, 40);
      async.elapse(const Duration(milliseconds: 149));
      expect(machine.resizes, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(machine.resizes, [(id: handle.id, cols: 100, rows: 40)]);

      tab.terminal.value.resize(100, 40);
      async.elapse(const Duration(seconds: 1));
      expect(machine.resizes, hasLength(1));
    });
  });

  test('Review Focus 4: a zero-sized viewport is never sent', () {
    fakeAsync((async) {
      tab.terminal.value.onResize!(0, 0, 0, 0);
      tab.terminal.value.onResize!(120, 0, 0, 0);
      async.elapse(const Duration(seconds: 1));
      expect(machine.resizes, isEmpty);
    });
  });

  test('exit shows a banner and stops input and resize', () {
    fakeAsync((async) {
      handle.emit(const TabExited(0));
      expect(tab.banner.value?.notice, TabNotice.exited);
      expect(tab.banner.value?.exitCode, 0);
      expect(tab.isLive.value, isFalse);

      tab.terminal.value.textInput('x');
      tab.terminal.value.resize(100, 40);
      async.elapse(const Duration(seconds: 1));
      expect(machine.inputs, isEmpty);
      expect(machine.resizes, isEmpty);
    });
  });

  test('closed on the computer stays the banner when session.exited follows', () {
    handle.emit(const TabDetached(DetachReason.closedByHost));
    handle.emit(const TabExited(0));
    expect(tab.banner.value?.notice, TabNotice.closedByHost);
  });

  test('spawn_failed keeps the reason for the banner', () {
    handle.emit(const TabError(AppErrorCode.spawnFailed, 'pwsh.exe not found'));
    expect(tab.banner.value?.notice, TabNotice.failed);
    expect(tab.banner.value?.errorCode, AppErrorCode.spawnFailed);
    expect(tab.banner.value?.detail, 'pwsh.exe not found');
  });

  test('Review Focus 3: session_not_found while reattaching ends the tab', () {
    handle.emit(const TabError(AppErrorCode.sessionNotFound, 'gone'));
    expect(tab.banner.value?.notice, TabNotice.sessionEnded);
    expect(tab.isLive.value, isFalse);
  });

  test('taken over → reattach attaches again with the current size and keeps the screen', () async {
    machine.sessions = [const SessionInfo(id: 101, index: 1, shell: 'zsh', createdAt: 0, attached: true)];
    tab.terminal.value.resize(100, 30);
    handle.emit(const TabOutput('before '));
    handle.emit(const TabDetached(DetachReason.takenOver));
    expect(tab.banner.value?.notice, TabNotice.takenOver);
    final before = tab.terminal.value;

    await tab.reattach();

    expect(machine.attached.single, (id: handle.id, cols: 100, rows: 30));
    expect(tab.banner.value, isNull);
    expect(tab.isLive.value, isTrue);
    expect(tab.terminal.value, same(before));
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
    expect(tab.banner.value?.notice, TabNotice.sessionEnded);
  });

  test('an ended placeholder tab is not live and drops input', () {
    final ended = TerminalTabController.ended(
      machine: machine,
      session: const SessionInfo(id: 7, index: 3, shell: 'bash', createdAt: 0, attached: false),
      modifiers: keys,
    );
    addTearDown(ended.dispose);
    expect(ended.banner.value?.notice, TabNotice.sessionEnded);
    expect(ended.title.value, 'bash 3');
    ended.terminal.value.textInput('x');
    expect(machine.inputs, isEmpty);
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd apps/mobile && flutter test test/features/terminal/terminal_tab_controller_test.dart`
Expected: FAIL — `Error when reading 'lib/features/terminal/presentation/controllers/terminal_tab_controller.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/mobile/lib/features/terminal/presentation/controllers/terminal_tab_controller.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/terminal/domain/shellx_terminal.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:xterm/xterm.dart';

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
class TerminalTabController extends Controller {
  TerminalTabController({
    required MachineSession machine,
    required TabHandle handle,
    required ModifierSource modifiers,
    required int cols,
    required int rows,
    this.resizeDebounce = const Duration(milliseconds: 150),
  }) : _machine = machine,
       _modifiers = modifiers,
       id = handle.id,
       _shell = handle.shell,
       _index = handle.index {
    _terminal = signal(_createTerminal(cols, rows));
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
  }) : _machine = machine,
       _modifiers = modifiers,
       id = session.id,
       _shell = session.shell,
       _index = session.index {
    _terminal = signal(_createTerminal(80, 24));
    _banner.value = const TabBanner(TabNotice.sessionEnded);
  }

  final int id;
  final Duration resizeDebounce;
  final MachineSession _machine;
  final ModifierSource _modifiers;
  final String _shell;
  final int _index;

  /// Selection state for long-press copy (spec §9.4).
  final TerminalController selection = TerminalController();
  late final Signal<ShellxTerminal> _terminal;
  final Signal<TabBanner?> _banner = signal(null);
  final Signal<bool> _bound = signal(false);
  final Signal<String?> _oscTitle = signal(null);
  late final Computed<bool> _isLive = computed(() => _bound.value && _banner.value == null);
  late final Computed<String> _title = computed(() => _oscTitle.value ?? '$_shell $_index');
  TabHandle? _handle;
  StreamSubscription<TabEvent>? _events;
  Timer? _resizeTimer;
  ({int cols, int rows})? _lastSent;
  bool _disposed = false;

  /// Replaced by a fresh instance on `session.reset`.
  ReadonlySignal<ShellxTerminal> get terminal => _terminal;
  ReadonlySignal<TabBanner?> get banner => _banner;
  ReadonlySignal<bool> get isLive => _isLive;

  /// Spec §7: the terminal title (OSC 0/2) if the shell set one, else "`<shell> <index>`".
  ReadonlySignal<String> get title => _title;

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
    _bound.value = true;
  }

  void _onEvent(TabEvent event) {
    switch (event) {
      case TabOutput(:final text):
        _terminal.peek().write(text);
      case TabReset():
        final current = _terminal.peek();
        _terminal.value = _createTerminal(current.viewWidth, current.viewHeight);
        selection.clearSelection();
      case TabExited(:final exitCode):
        // "Closed on the computer" says more than the exit code that follows it.
        if (_banner.peek()?.notice != TabNotice.closedByHost) {
          _banner.value = TabBanner(TabNotice.exited, exitCode: exitCode);
        }
      case TabDetached(:final reason):
        _banner.value = TabBanner(reason == DetachReason.takenOver ? TabNotice.takenOver : TabNotice.closedByHost);
      case TabError(:final code, :final message):
        _banner.value = code == AppErrorCode.sessionNotFound
            ? const TabBanner(TabNotice.sessionEnded)
            : TabBanner(TabNotice.failed, errorCode: code, detail: message);
    }
  }

  void _onUserInput(String data) {
    if (!_isLive.peek()) return;
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
    if (_disposed || !_isLive.peek() || cols < 1 || rows < 1) return;
    final size = (cols: cols, rows: rows);
    if (size == _lastSent) return;
    _lastSent = size;
    _machine.resize(id, cols, rows);
  }

  void _onTitle(String title) {
    if (_disposed) return;
    _oscTitle.value = title.isEmpty ? null : title;
  }

  /// After `taken_over`: attach this phone again (the other device gets
  /// `taken_over`). `shellx_client` re-attaches the same tab with
  /// `last_seq = received`, so the catch-up output arrives on the events we
  /// are still listening to and the current screen is kept; a `session.reset`
  /// replaces it as usual.
  Future<void> reattach() async {
    if (_banner.peek()?.notice != TabNotice.takenOver) return;
    final current = _terminal.peek();
    final cols = current.viewWidth;
    final rows = current.viewHeight;
    try {
      final handle = await _machine.attach(id, cols: cols, rows: rows);
      if (_disposed) return;
      if (!identical(handle, _handle)) {
        unawaited(_events?.cancel());
        _bind(handle);
      }
      _banner.value = null;
      _lastSent = (cols: cols, rows: rows);
    } on AppErrorException catch (error) {
      if (error.code != AppErrorCode.sessionNotFound) rethrow;
      if (!_disposed) _banner.value = const TabBanner(TabNotice.sessionEnded);
    }
  }

  void dispose() {
    _disposed = true;
    _resizeTimer?.cancel();
    unawaited(_events?.cancel());
    selection.dispose();
    _isLive.dispose();
    _title.dispose();
    _terminal.dispose();
    _banner.dispose();
    _bound.dispose();
    _oscTitle.dispose();
  }
}
```

- [ ] **Step 4: Run the test and the analyzer**

```bash
cd apps/mobile
flutter test test/features/terminal/terminal_tab_controller_test.dart
flutter analyze
```

Expected: `+13: All tests passed!`; `No issues found!`. (The whole suite: `+254`.)

- [ ] **Step 5: Commit**

```bash
git add apps/mobile
git commit -m "feat(mobile): terminal tab controller for output, input, resize and tab lifecycle"
```

---

### Task 13: `TerminalWorkspace` and `WorkspaceRegistry` — the tabs of one machine

**Files:**
- Create: `apps/mobile/lib/features/terminal/presentation/controllers/terminal_workspace.dart`
- Test: `apps/mobile/test/features/terminal/terminal_workspace_test.dart`

**Interfaces:**
- Consumes: `MachineSession`, `ShellxBackend.machine` (Task 10); `SessionHolder.backend` (Task 11); `MachineReady`, `MachineFailed`, `AppErrorException`, `AppErrorCode`, `SessionInfo`; `ExtraKeysController` (Task 6); `TerminalTabController` (Task 12); `TerminalGrid` (Task 8).
- Produces:
  - `class TerminalWorkspace extends Controller { TerminalWorkspace({required MachineSession machine, ExtraKeysController? extraKeys}); final MachineSession machine; final ExtraKeysController extraKeys; ReadonlySignal<List<TerminalTabController>> get tabs; ReadonlySignal<int> get activeIndex; ReadonlySignal<TerminalTabController?> get activeTab; void select(int index); Future<void> ensureConnected(); Future<List<SessionInfo>?> prepare(); Future<TerminalTabController> openNew(TerminalGrid grid); Future<TerminalTabController> attach(SessionInfo session, TerminalGrid grid); Future<void> close(TerminalTabController tab); void dispose(); }`
  - `@lazySingleton class WorkspaceRegistry { WorkspaceRegistry(ReadonlySignal<ShellxBackend?> backend); @factoryMethod static WorkspaceRegistry create(SessionHolder session); TerminalWorkspace forMachine(String agentId); void remove(String agentId); int tabCount(String agentId); @disposeMethod void dispose(); }`

`ensureConnected()` normalises the contract's "ném theo MachineFailed" (overview §5.7; plan 03 throws `MachineConnectionException` after setting `MachineFailed`): whatever `connect()` throws, the `MachineFailed` state is rethrown so the UI can map it — requests made later (`openSession`, `attach`, `listSessions`) may still throw `MachineConnectionException`, which `ErrorText` and the page also handle. `prepare()` sends `session.list` only on the first visit of a machine in this sign-in (spec §9.2 #4). The registry keeps workspaces alive across page visits so terminals keep receiving output (spec §9.4), follows `SessionHolder.backend` (a sign-out or another sign-in disposes the previous account's workspaces) and counts the tabs for the machine list's "N tab" pill.

- [ ] **Step 1: Write the failing test**

`apps/mobile/test/features/terminal/terminal_workspace_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_tab_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';

import '../../support/fakes.dart';

void main() {
  const grid = (cols: 80, rows: 24);
  const running = SessionInfo(id: 7, index: 1, shell: 'zsh', createdAt: 1790000000000, attached: false);
  late FakeBackend backend;
  late FakeMachineSession machine;
  late Signal<ShellxBackend?> signedIn;
  late WorkspaceRegistry registry;
  late TerminalWorkspace workspace;

  setUp(() {
    backend = FakeBackend(pinnedList: [pinned(agentA)]);
    machine = backend.addMachine(agentA);
    signedIn = signal<ShellxBackend?>(backend);
    registry = WorkspaceRegistry(signedIn);
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
    expect(workspace.tabs.value, [first, second]);
    expect(workspace.activeTab.value, same(second));
    workspace.select(0);
    expect(workspace.activeTab.value, same(first));
  });

  test('session_limit surfaces as AppErrorException and adds no tab', () async {
    machine.openError = const AppErrorException(AppErrorCode.sessionLimit, 'limit');
    await expectLater(workspace.openNew(grid), throwsA(isA<AppErrorException>()));
    expect(workspace.tabs.value, isEmpty);
  });

  test('attach adds a live tab; attaching the same session again just selects it', () async {
    machine.sessions = [running];
    final tab = await workspace.attach(running, grid);
    await workspace.openNew(grid);
    expect(await workspace.attach(running, grid), same(tab));
    expect(workspace.activeTab.value, same(tab));
    expect(machine.attached, hasLength(1));
    expect(tab.isLive.value, isTrue);
  });

  test('Review Focus 3: attach → session_not_found gives a closable "ended" tab', () async {
    machine.attachErrors[running.id] = const AppErrorException(AppErrorCode.sessionNotFound, 'gone');
    final tab = await workspace.attach(running, grid);
    expect(tab.banner.value?.notice, TabNotice.sessionEnded);
    expect(workspace.tabs.value, [tab]);

    await workspace.close(tab);
    expect(workspace.tabs.value, isEmpty);
  });

  test('close sends session.close, keeps a valid selection, ignores machine errors', () async {
    final a = await workspace.openNew(grid);
    final b = await workspace.openNew(grid);
    await workspace.close(b);
    expect(machine.closed, [b.id]);
    expect(workspace.activeTab.value, same(a));
    await workspace.close(a);
    expect(workspace.activeTab.value, isNull);
  });

  test('remove disposes the workspace of an unpaired machine', () async {
    await workspace.openNew(grid);
    registry.remove(agentA);
    backend.addMachine(agentA);
    expect(registry.forMachine(agentA), isNot(same(workspace)));
  });

  test('another sign-in drops the previous account\'s workspaces; signed out refuses', () async {
    await workspace.openNew(grid);
    final next = FakeBackend(pinnedList: [pinned(agentA)])..addMachine(agentA);
    signedIn.value = next;
    expect(registry.forMachine(agentA).machine, same(next.machines[agentA]));

    signedIn.value = null;
    expect(() => registry.forMachine(agentA), throwsStateError);
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd apps/mobile && flutter test test/features/terminal/terminal_workspace_test.dart`
Expected: FAIL — `Error when reading 'lib/features/terminal/presentation/controllers/terminal_workspace.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/mobile/lib/features/terminal/presentation/controllers/terminal_workspace.dart`:

```dart
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_tab_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/terminal_metrics.dart';

/// The tabs of one machine. Outlives its page so terminals keep receiving
/// output while the user is elsewhere in the app (spec §9.4).
class TerminalWorkspace extends Controller {
  TerminalWorkspace({required this.machine, ExtraKeysController? extraKeys})
    : extraKeys = extraKeys ?? ExtraKeysController();

  final MachineSession machine;
  final ExtraKeysController extraKeys;
  final Signal<List<TerminalTabController>> _tabs = signal(const []);
  final Signal<int> _active = signal(0);
  late final Computed<TerminalTabController?> _activeTab = computed(() {
    final tabs = _tabs.value;
    return tabs.isEmpty ? null : tabs[_active.value];
  });
  bool _listedSessions = false;

  ReadonlySignal<List<TerminalTabController>> get tabs => _tabs;
  ReadonlySignal<int> get activeIndex => _active;
  ReadonlySignal<TerminalTabController?> get activeTab => _activeTab;

  void select(int index) {
    if (index < 0 || index >= _tabs.peek().length) return;
    _active.value = index;
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

  /// Spec §9.2 #4: the first time the machine page opens, send
  /// `session.list`. Returns the sessions not shown as tabs yet, or null on
  /// later visits.
  Future<List<SessionInfo>?> prepare() async {
    await ensureConnected();
    if (_listedSessions) return null;
    final sessions = await machine.listSessions();
    _listedSessions = true;
    return [
      for (final session in sessions)
        if (!_tabs.peek().any((tab) => tab.id == session.id)) session,
    ];
  }

  /// Throws [AppErrorException] (`session_limit`, `spawn_failed`).
  Future<TerminalTabController> openNew(TerminalGrid grid) async {
    await ensureConnected();
    final handle = await machine.openSession(cols: grid.cols, rows: grid.rows);
    return _add(
      TerminalTabController(
        machine: machine,
        handle: handle,
        modifiers: extraKeys,
        cols: grid.cols,
        rows: grid.rows,
      ),
    );
  }

  /// Attaches an existing session. Review Focus 3: when the session is gone
  /// (`session_not_found`), the tab still appears, showing "Phiên đã kết thúc".
  Future<TerminalTabController> attach(SessionInfo session, TerminalGrid grid) async {
    final tabs = _tabs.peek();
    final existing = tabs.indexWhere((tab) => tab.id == session.id);
    if (existing >= 0) {
      select(existing);
      return tabs[existing];
    }
    await ensureConnected();
    try {
      final handle = await machine.attach(session.id, cols: grid.cols, rows: grid.rows);
      return _add(
        TerminalTabController(
          machine: machine,
          handle: handle,
          modifiers: extraKeys,
          cols: grid.cols,
          rows: grid.rows,
        ),
      );
    } on AppErrorException catch (error) {
      if (error.code != AppErrorCode.sessionNotFound) rethrow;
      return _add(TerminalTabController.ended(machine: machine, session: session, modifiers: extraKeys));
    }
  }

  TerminalTabController _add(TerminalTabController tab) {
    final tabs = [..._tabs.peek(), tab];
    batch(() {
      _tabs.value = List.unmodifiable(tabs);
      _active.value = tabs.length - 1;
    });
    return tab;
  }

  /// `×`: sends `session.close` (spec §6.4) and drops the tab. Errors from an
  /// already-ended session are ignored — the tab must always be closable.
  Future<void> close(TerminalTabController tab) async {
    final tabs = [..._tabs.peek()];
    if (!tabs.remove(tab)) return;
    batch(() {
      _tabs.value = List.unmodifiable(tabs);
      if (_active.peek() >= tabs.length) _active.value = tabs.isEmpty ? 0 : tabs.length - 1;
    });
    tab.dispose();
    try {
      await machine.closeTab(tab.id);
    } on Object {
      // The session no longer exists on the machine.
    }
  }

  void dispose() {
    for (final tab in _tabs.peek()) {
      tab.dispose();
    }
    _activeTab.dispose();
    _tabs.dispose();
    _active.dispose();
    extraKeys.dispose();
  }
}

/// One [TerminalWorkspace] per machine for the signed-in account. A sign-out or a new sign-in
/// (another backend) disposes every workspace of the previous one.
@lazySingleton
class WorkspaceRegistry {
  WorkspaceRegistry(ReadonlySignal<ShellxBackend?> backend) : _backend = backend {
    _stopWatching = backend.subscribe((current) {
      if (identical(current, _owner)) return;
      _clear();
      _owner = current;
    });
  }

  @factoryMethod
  static WorkspaceRegistry create(SessionHolder session) => WorkspaceRegistry(session.backend);

  final ReadonlySignal<ShellxBackend?> _backend;
  final Map<String, TerminalWorkspace> _workspaces = {};
  late final void Function() _stopWatching;
  ShellxBackend? _owner;

  /// Throws [StateError] when signed out or when [agentId] is not pinned.
  TerminalWorkspace forMachine(String agentId) {
    final backend = _backend.peek() ?? (throw StateError('Not signed in'));
    return _workspaces.putIfAbsent(agentId, () => TerminalWorkspace(machine: backend.machine(agentId)));
  }

  /// After unpairing (spec §5.5) or when the machine stops trusting us.
  void remove(String agentId) => _workspaces.remove(agentId)?.dispose();

  /// Tabs open on this phone for [agentId] (the "2 tab" pill of the machine list); read inside
  /// `Watch` it follows the workspace's tabs.
  int tabCount(String agentId) => _workspaces[agentId]?.tabs.value.length ?? 0;

  void _clear() {
    for (final workspace in _workspaces.values) {
      workspace.dispose();
    }
    _workspaces.clear();
  }

  @disposeMethod
  void dispose() {
    _stopWatching();
    _clear();
  }
}
```

- [ ] **Step 4: Generate, run the test, analyze**

```bash
cd apps/mobile
dart run build_runner build
flutter test test/features/terminal/terminal_workspace_test.dart
flutter analyze
flutter test
```

Expected: `+10: All tests passed!`; `No issues found!`; `+264: All tests passed!`.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile
git commit -m "feat(mobile): per-machine terminal workspaces with a registry"
```

---

### Task 14: Terminal page — chrome bar, tabs, session sheet, xterm view, extra keys, copy/paste, notices

UI per the design's terminal screens (binding): a dark chrome bar (`TerminalColors.chrome`) with the back button, the machine name and a status line — "Đã kết nối · mã hóa đầu cuối" (green dot), "Đang kết nối…" or "Mất kết nối, đang thử lại…" (amber) — and an "Aa" button that opens a font-size slider sheet; a row of tabs (live dot, title, `×`) with `+` at the end; the xterm view in JetBrains Mono on the `--t-*` theme; the extra keys bar right above the keyboard. First visit of a machine with running sessions → a bottom sheet "Máy này đang có {n} phiên" (rows with "Mở", then "Mở phiên mới"); without sessions → a new session opens directly. An exited or vanished session keeps its output and shows the "Phiên đã kết thúc" card with "Đóng tab" / "Mở phiên mới"; `spawn_failed` shows the reason; a taken-over tab offers "Gắn lại". `session_limit` and other failures are a floating notice at the top that goes away after 4 s. Landscape: name and tabs share one bar, with a keyboard toggle. After 4001 a banner offers "Kết nối lại".

**Files:**
- Create: `apps/mobile/lib/features/app/connection_banner.dart`
- Create: `apps/mobile/lib/features/terminal/presentation/widgets/session_picker.dart`
- Create: `apps/mobile/lib/features/terminal/presentation/controllers/terminal_page_controller.dart`
- Create: `apps/mobile/lib/features/terminal/presentation/pages/terminal_page.dart`
- Modify: `apps/mobile/test/support/fakes.dart` (append `FakeSessionHolder`)
- Test: `apps/mobile/test/features/terminal/terminal_page_test.dart`

**Interfaces:**
- Consumes: `SessionHolder` (`requireBackend`, `reconnectReplaced`) (Task 11); `ShellxBackend`, `MachineSession` (Task 10); `ErrorText` via `Controller.errorFactory` (Task 9); `ExtraKeysBar` (Task 7); `TerminalTabController`, `TabBanner`, `TabNotice` (Task 12); `measureTerminalGrid`, `fallbackGrid`, `shellxTerminalStyle`, `PinchToZoom` (Task 8); `TerminalWorkspace`, `WorkspaceRegistry` (Task 13); `terminalShortcuts` (Task 5); `AppSettings` (Task 3); `TerminalColors` (Task 2); `TerminalView` (`xterm`); `Clipboard`.
- Produces:
  - `class ConnectionBanner extends StatefulWidget { const ConnectionBanner({Key? key, required ShellxBackend backend, required VoidCallback onReconnectReplaced, bool showReconnecting = true, EdgeInsets padding}); }` — "Mất kết nối, đang thử lại…" while disconnected/reconnecting (not during the very first connect), "Một phiên bản khác của app đã kết nối." + "Kết nối lại" after 4001.
  - `sealed class SessionChoice`, `final class AttachSession extends SessionChoice { const AttachSession(SessionInfo session); }`, `final class OpenNewSession extends SessionChoice { const OpenNewSession(); }`, `Future<SessionChoice?> showSessionPicker(BuildContext context, List<SessionInfo> sessions, {DateTime? now})`
  - `enum TerminalExit { untrusted, updateRequired }` — what the page pops with when the machine cannot be used.
  - `@injectable class TerminalPageController extends Controller { TerminalPageController(@factoryParam String agentId, WorkspaceRegistry registry, SessionHolder session, AppSettings settings); static const Duration noticeDuration; late final TerminalWorkspace workspace; ShellxBackend get backend; ReadonlySignal<double> fontSize; ReadonlySignal<bool> busy, canOpen; ReadonlySignal<String?> notice; ReadonlySignal<TerminalExit?> exit; ReadonlySignal<MachineConnectionState> machineState; ReadonlySignal<RelayConnectionState> relayState; void setFontSize(double); Future<List<SessionInfo>?> prepare(); Future<void> openNew(TerminalGrid); Future<void> attach(SessionInfo, TerminalGrid); Future<void> close(TerminalTabController); Future<void> replaceWithNew(TerminalTabController ended, TerminalGrid); void sendKey(ExtraKey); void paste(String); void reconnectReplaced(); void dismissNotice(); void dispose(); }` — resolved with `getIt<TerminalPageController>(param1: agentId)`.
  - `@RoutePage() class TerminalPage extends StatefulWidget { const TerminalPage({Key? key, required String agentId, required String machineName}); }` → generated `TerminalRoute(agentId:, machineName:)`.
  - Test support: `FakeSessionHolder([ShellxBackend? backend])` — signed in around `backend` (signed out without one), records `authCalls`, `logoutCalls`, `reconnectCalls`, `deletePasswords`; scriptable `authError`, `deleteError`, `lastEmail`, `signOutReasonValue`.

Behaviour (spec §9.2 #4, §9.4, §12): first visit → connect + `session.list`; `+` opens, `×` closes (confirmation for live sessions, none for ended ones); tabs keyed `ValueKey('tab-<id>')`; the active tab renders a `TerminalView` (read-only when not live, platform shortcuts, `deleteDetection`) inside `PinchToZoom`; long-press selection shows "Sao chép"; the bar's "Dán" pastes the clipboard through `ShellxTerminal.paste`; `MachineFailed(untrusted)` → the workspace is dropped, the machine unpaired, and the page pops with `TerminalExit.untrusted`; `proto_unsupported` → pops with `TerminalExit.updateRequired`; every other failure → the floating notice with the `ErrorText` text. The workspace outlives the page (Task 13), so leaving and coming back keeps the tabs.

- [ ] **Step 1: Add the session holder fake**

Append to `apps/mobile/test/support/fakes.dart`:

```dart
/// A [SessionHolder] for page tests: signed in around [backend] (or signed out without one),
/// recording what the pages ask of it.
class FakeSessionHolder implements SessionHolder {
  FakeSessionHolder([ShellxBackend? backend])
    : _backend = signal<ShellxBackend?>(backend),
      _session = signal<AccountSession?>(
        backend == null
            ? null
            : const AccountSession(userId: 'user-1', deviceId: 'device-1', token: 'token-1', email: 'me@example.com'),
      );

  final Signal<ShellxBackend?> _backend;
  final Signal<AccountSession?> _session;
  final Signal<SignOutReason?> _signOutReason = signal(null);
  int reconnectCalls = 0;
  int logoutCalls = 0;
  final List<String> deletePasswords = [];
  Object? deleteError;
  final List<(String, String, String)> authCalls = [];
  Object? authError;

  @override
  String? lastEmail;

  set signOutReasonValue(SignOutReason? reason) => _signOutReason.value = reason;

  @override
  ReadonlySignal<ShellxBackend?> get backend => _backend;

  @override
  ShellxBackend get requireBackend => _backend.peek() ?? (throw StateError('Not signed in'));

  @override
  ReadonlySignal<AccountSession?> get session => _session;

  @override
  ReadonlySignal<SignOutReason?> get signOutReason => _signOutReason;

  @override
  String get appVersion => '1.0.0';

  @override
  Future<void> login(String email, String password) => _auth('login', email, password);

  @override
  Future<void> register(String email, String password) => _auth('register', email, password);

  Future<void> _auth(String kind, String email, String password) async {
    authCalls.add((kind, email, password));
    final error = authError;
    if (error != null) throw error;
  }

  @override
  Future<void> reconnectReplaced() async => reconnectCalls++;

  @override
  Future<void> logout() async => logoutCalls++;

  @override
  Future<void> deleteAccount(String password) async {
    deletePasswords.add(password);
    final error = deleteError;
    if (error != null) throw error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
```

- [ ] **Step 2: Write the failing widget tests**

`apps/mobile/test/features/terminal/terminal_page_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_page_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';
import 'package:shellx_mobile/features/terminal/presentation/widgets/extra_keys_bar.dart';
import 'package:xterm/xterm.dart';

import '../../support/app_harness.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fakes.dart';

void main() {
  const running = SessionInfo(id: 7, index: 1, shell: 'zsh', createdAt: 1790000000000, attached: true);
  late FakeBackend backend;
  late FakeMachineSession machine;
  late FakeSessionHolder session;
  late WorkspaceRegistry registry;
  late List<Object?> results;

  setUp(() {
    backend = FakeBackend(pinnedList: [pinned(agentA)]);
    machine = backend.addMachine(agentA);
    session = FakeSessionHolder(backend);
    registry = WorkspaceRegistry(session.backend);
    final settings = AppSettings(InMemoryKeyValueStore());
    results = [];
    getIt
      ..registerSingleton<PopupHandler>(FakePopupHandler())
      ..registerFactoryParam<TerminalPageController, String, void>(
        (agentId, _) => TerminalPageController(agentId, registry, session, settings),
      );
  });

  tearDown(() async {
    registry.dispose();
    await getIt.reset();
  });

  /// A portrait phone (390 × 844 pt) unless the test set another size first.
  Future<void> open(WidgetTester tester, {bool portrait = true}) async {
    if (portrait) {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(
      routedApp(
        open: () => TerminalRoute(agentId: agentA, machineName: 'MacBook-Pro'),
        routes: [AutoRoute(page: TerminalRoute.page)],
        results: results,
      ),
    );
    await tester.pumpAndSettle();
    await openPushed(tester);
  }

  String lastInput() => utf8.decode(machine.inputs.last.data);
  String screen() => registry.forMachine(agentA).activeTab.value!.terminal.value.buffer.getText();

  testWidgets('first open without sessions opens a tab automatically; the chrome shows the machine', (tester) async {
    await open(tester);
    expect(find.text('MacBook-Pro'), findsOneWidget);
    expect(find.text('Đã kết nối · mã hóa đầu cuối'), findsOneWidget);
    expect(machine.listCalls, 1);
    expect(machine.opened, hasLength(1));
    expect(machine.opened.single.cols, greaterThanOrEqualTo(1));
    expect(machine.opened.single.rows, greaterThanOrEqualTo(1));
    expect(find.text('zsh 1'), findsOneWidget);

    machine.handles.single.emit(const TabOutput('hello'));
    expect(screen(), contains('hello'));
    expect(tester.widget<TerminalView>(find.byType(TerminalView)).theme.background, TerminalColors.background);
  });

  testWidgets('first open offers the running sessions in a sheet; later visits do not list', (tester) async {
    machine.sessions = [running];
    await open(tester);
    expect(find.text('Máy này đang có 1 phiên'), findsOneWidget);
    expect(find.textContaining('đang mở trên thiết bị khác'), findsOneWidget);

    await tester.tap(find.text('Mở'));
    await tester.pumpAndSettle();
    expect(machine.attached.single.id, 7);
    expect(find.text('zsh 1'), findsOneWidget);

    await tester.tap(find.byTooltip('Về danh sách máy'));
    await tester.pumpAndSettle();
    await openPushed(tester);
    expect(machine.listCalls, 1);
    expect(find.text('Máy này đang có 1 phiên'), findsNothing);
    expect(find.text('zsh 1'), findsOneWidget);
  });

  testWidgets('+ opens another tab; × asks before closing a live session', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Mở phiên mới'));
    await tester.pumpAndSettle();
    expect(find.text('zsh 2'), findsOneWidget);

    await tester.tap(
      find.descendant(of: find.byKey(const ValueKey('tab-102')), matching: find.byTooltip('Đóng phiên')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Đóng phiên này? Mọi chương trình đang chạy trong phiên sẽ bị dừng.'), findsOneWidget);
    await tester.tap(find.text('Đóng phiên'));
    await tester.pumpAndSettle();
    expect(machine.closed, [102]);
    expect(find.text('zsh 2'), findsNothing);
  });

  testWidgets('Review Focus 3: a session that vanished shows "Phiên đã kết thúc" and can be closed', (tester) async {
    machine.sessions = [running];
    machine.attachErrors[7] = const AppErrorException(AppErrorCode.sessionNotFound, 'gone');
    await open(tester);
    await tester.tap(find.text('Mở'));
    await tester.pumpAndSettle();

    expect(find.text('Phiên đã kết thúc'), findsOneWidget);
    expect(find.text('Máy tính không còn phiên này. Nội dung ở trên vẫn đọc và copy được.'), findsOneWidget);
    await tester.tap(find.text('Đóng tab'));
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

  testWidgets('design: an exited session keeps its content; "Mở phiên mới" replaces the tab', (tester) async {
    await open(tester);
    machine.handles.single.emit(const TabOutput('Built build/ios/iphoneos/Runner.app'));
    machine.handles.single.emit(const TabExited(0));
    await tester.pump();
    expect(find.text('Phiên đã kết thúc'), findsOneWidget);
    expect(find.text('Lệnh cuối thoát với mã 0. Nội dung ở trên vẫn đọc và copy được.'), findsOneWidget);
    expect(screen(), contains('Runner.app'));

    await tester.tap(find.text('Mở phiên mới'));
    await tester.pumpAndSettle();
    expect(machine.opened, hasLength(2));
    expect(machine.closed, [101]);
    expect(find.text('zsh 2'), findsOneWidget);
    expect(find.text('Phiên đã kết thúc'), findsNothing);
  });

  testWidgets('spawn_failed shows the reason in the tab', (tester) async {
    await open(tester);
    machine.handles.single.emit(const TabError(AppErrorCode.spawnFailed, 'pwsh.exe not found'));
    await tester.pump();
    expect(find.text('Không mở được shell: pwsh.exe not found'), findsOneWidget);
  });

  testWidgets('taken over: "Gắn lại" attaches this phone again', (tester) async {
    await open(tester);
    machine.reuseHandles = true;
    machine.handles.single.emit(const TabDetached(DetachReason.takenOver));
    await tester.pump();
    expect(find.text('Phiên đang được mở trên thiết bị khác.'), findsOneWidget);
    await tester.tap(find.text('Gắn lại'));
    await tester.pumpAndSettle();
    expect(machine.attached.single.id, 101);
    expect(find.text('Phiên đang được mở trên thiết bị khác.'), findsNothing);
  });

  testWidgets('session_limit is a floating notice that goes away', (tester) async {
    await open(tester);
    machine.openError = const AppErrorException(AppErrorCode.sessionLimit, 'limit');
    await tester.tap(find.byTooltip('Mở phiên mới'));
    await tester.pumpAndSettle();
    expect(find.text('Máy đã mở tối đa 10 phiên. Hãy đóng bớt phiên.'), findsOneWidget);
    await tester.pump(TerminalPageController.noticeDuration);
    expect(find.text('Máy đã mở tối đa 10 phiên. Hãy đóng bớt phiên.'), findsNothing);
  });

  testWidgets('an untrusted machine is unpaired and the page closes with the reason (spec §12)', (tester) async {
    machine.connectFailure = MachineConnectionFailure.untrusted;
    await open(tester);
    await tester.pumpAndSettle();
    expect(backend.unpaired, [agentA]);
    expect(results, [TerminalExit.untrusted]);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('proto_unsupported closes the page asking for an update', (tester) async {
    machine.connectFailure = MachineConnectionFailure.protocolUnsupported;
    await open(tester);
    await tester.pumpAndSettle();
    expect(results, [TerminalExit.updateRequired]);
    expect(backend.unpaired, isEmpty);
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

  testWidgets('"Aa" opens the font size slider', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Cỡ chữ'));
    await tester.pumpAndSettle();
    tester.widget<Slider>(find.byType(Slider)).onChanged!(20);
    await tester.pumpAndSettle();
    expect(tester.widget<TerminalView>(find.byType(TerminalView)).textStyle.fontSize, 20);
    await tester.pump(const Duration(seconds: 1)); // let the debounced resize fire
  });

  testWidgets('the status line follows the relay; 4001 offers "Kết nối lại"', (tester) async {
    await open(tester);
    backend.emitRelay(RelayConnectionState.disconnected);
    await tester.pump();
    expect(find.text('Mất kết nối, đang thử lại…'), findsOneWidget);
    backend.emitRelay(RelayConnectionState.connected);
    await tester.pump();
    expect(find.text('Đã kết nối · mã hóa đầu cuối'), findsOneWidget);

    backend.emitRelay(RelayConnectionState.replaced);
    await tester.pump();
    expect(find.text('Một phiên bản khác của app đã kết nối.'), findsOneWidget);
    await tester.tap(find.text('Kết nối lại'));
    expect(session.reconnectCalls, 1);
    await tester.pump(const Duration(seconds: 1)); // let the debounced resize fire
  });

  testWidgets('landscape: name and tabs share the bar, with a keyboard button', (tester) async {
    tester.view.physicalSize = const Size(2532, 1170);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await open(tester, portrait: false);
    expect(find.byTooltip('Bàn phím'), findsOneWidget);
    expect(find.byTooltip('Cỡ chữ'), findsNothing);
    expect(
      tester.getCenter(find.text('MacBook-Pro')).dy,
      moreOrLessEquals(tester.getCenter(find.text('zsh 1')).dy, epsilon: 4),
    );
  });
}
```

- [ ] **Step 3: Run them to see them fail**

Run: `cd apps/mobile && flutter test test/features/terminal/terminal_page_test.dart`
Expected: FAIL — `TerminalPageController`, `TerminalPage`, `TerminalRoute` are not defined.

- [ ] **Step 4: Connection banner and session sheet**

`apps/mobile/lib/features/app/connection_banner.dart`:

```dart
import 'dart:async';

import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Spec §12: "Mất kết nối, đang thử lại…" while the relay reconnects, and a
/// manual "Kết nối lại" after close code 4001 (no automatic reconnect).
class ConnectionBanner extends StatefulWidget {
  const ConnectionBanner({
    super.key,
    required this.backend,
    required this.onReconnectReplaced,
    this.showReconnecting = true,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 8),
  });

  final ShellxBackend backend;
  final VoidCallback onReconnectReplaced;

  /// False on the terminal page, whose status line already says "Mất kết nối, đang thử lại…".
  final bool showReconnecting;
  final EdgeInsets padding;

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
    final strings = S.of(context);
    final reconnecting =
        _state == RelayConnectionState.disconnected ||
        (_state == RelayConnectionState.connecting && _hadConnectionOrFailure);
    final replaced = _state == RelayConnectionState.replaced;
    if (!(reconnecting && widget.showReconnecting) && !replaced) return const SizedBox.shrink();
    return Padding(
      padding: widget.padding,
      child: NoticeBanner(
        text: reconnecting ? strings.bannerReconnecting : strings.bannerReplaced,
        leading: reconnecting ? const NoticeSpinner() : const Icon(Icons.link_off),
        action: replaced
            ? TextButton(onPressed: widget.onReconnectReplaced, child: Text(strings.bannerReconnectButton))
            : null,
      ),
    );
  }
}
```

`apps/mobile/lib/features/terminal/presentation/widgets/session_picker.dart`:

```dart
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/machines/presentation/last_seen.dart';
import 'package:shellx_mobile/shared/shared.dart';

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

/// Spec §9.2 #4 / design "Chọn phiên có sẵn": the bottom sheet shown on the first visit of a
/// machine that already runs sessions. Returns null when dismissed.
Future<SessionChoice?> showSessionPicker(BuildContext context, List<SessionInfo> sessions, {DateTime? now}) {
  return showModalBottomSheet<SessionChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (context) {
      final strings = S.of(context);
      final colors = context.colors;
      final at = now ?? DateTime.now();
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(strings.pickerTitle(sessions.length), style: context.typo.heading20.heavy),
              6.sizedHeight,
              Text(strings.pickerSubtitle, style: context.typo.subHeader15.copyWith(color: colors.secondaryText)),
              14.sizedHeight,
              Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.divider),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (i, session) in sessions.indexed) ...[
                      if (i > 0) Divider(height: 1, color: colors.divider),
                      InkWell(
                        onTap: () => Navigator.pop(context, AttachSession(session)),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 56),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${session.shell} ${session.index}',
                                        style: TextStyle(
                                          fontFamily: FontFamily.jetBrainsMono,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14.5,
                                          color: colors.primaryText,
                                        ),
                                      ),
                                      2.sizedHeight,
                                      Text(
                                        [
                                          strings.pickerStarted(
                                            formatLastSeen(
                                              strings,
                                              DateTime.fromMillisecondsSinceEpoch(session.createdAt),
                                              at,
                                            ),
                                          ),
                                          if (session.attached) strings.pickerAttachedElsewhere,
                                        ].join(' · '),
                                        style: context.typo.paragraph13.copyWith(color: colors.secondaryText),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  strings.pickerOpen,
                                  style: context.typo.subHeader15.bold.copyWith(color: colors.primary),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              14.sizedHeight,
              AppButton(
                title: strings.terminalOpenNew,
                prefix: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.add, color: colors.onPrimary),
                ),
                onTap: () => Navigator.pop(context, const OpenNewSession()),
              ),
            ],
          ),
        ),
      );
    },
  );
}
```

- [ ] **Step 5: Page controller**

`apps/mobile/lib/features/terminal/presentation/controllers/terminal_page_controller.dart`:

```dart
import 'dart:async';

import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_tab_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';
import 'package:shellx_mobile/features/terminal/presentation/terminal_metrics.dart';

/// Why the terminal page closed itself; the machine list reacts (design "Khi có sự cố").
enum TerminalExit {
  /// HS2 `untrusted`: the pin is dropped; the list offers "Quét mã" (spec §12).
  untrusted,

  /// HS2 `proto_unsupported`: "Cần cập nhật app" (spec §12).
  updateRequired,
}

/// The terminal page of one machine (spec §9.2 #4). The tabs live in the machine's
/// [TerminalWorkspace], which outlives the page; failures show a floating notice with the spec
/// §12 text.
@injectable
class TerminalPageController extends Controller {
  TerminalPageController(@factoryParam this.agentId, this._registry, this._session, AppSettings settings)
    : _fontSize = signal(settings.fontSize.peek()) {
    final machine = workspace.machine;
    _machineState = signal(machine.state);
    _machineStates = machine.states.listen((state) => _machineState.value = state);
    final backend = _session.requireBackend;
    _relayState = signal(backend.relayState);
    _relayStates = backend.relayStates.listen((state) => _relayState.value = state);
  }

  static const Duration noticeDuration = Duration(seconds: 4);

  final String agentId;
  final WorkspaceRegistry _registry;
  final SessionHolder _session;
  final Signal<double> _fontSize;
  final Signal<bool> _busy = signal(false);
  final Signal<String?> _notice = signal(null);
  final Signal<TerminalExit?> _exit = signal(null);
  late final Signal<MachineConnectionState> _machineState;
  late final Signal<RelayConnectionState> _relayState;
  late final StreamSubscription<MachineConnectionState> _machineStates;
  late final StreamSubscription<RelayConnectionState> _relayStates;
  late final Computed<bool> _canOpen = computed(() => !_busy.value);
  Timer? _noticeTimer;
  bool _disposed = false;

  late final TerminalWorkspace workspace = _registry.forMachine(agentId);

  ShellxBackend get backend => _session.requireBackend;

  /// Font size of this page (pinch or "Aa"); the default comes from Settings (spec §9.2 #5).
  ReadonlySignal<double> get fontSize => _fontSize;

  /// A machine operation is running (progress bar, `+` disabled).
  ReadonlySignal<bool> get busy => _busy;
  ReadonlySignal<bool> get canOpen => _canOpen;

  /// The floating notice (e.g. `session_limit`); cleared after [noticeDuration].
  ReadonlySignal<String?> get notice => _notice;

  /// Set when the page must close (the machine list then shows the matching screen).
  ReadonlySignal<TerminalExit?> get exit => _exit;

  /// For the status line under the machine name.
  ReadonlySignal<MachineConnectionState> get machineState => _machineState;
  ReadonlySignal<RelayConnectionState> get relayState => _relayState;

  void setFontSize(double size) => _fontSize.value = AppSettings.clampFontSize(size);

  /// First visit: connect and `session.list`; null on later visits or on error.
  Future<List<SessionInfo>?> prepare() => _run<List<SessionInfo>?>(workspace.prepare);

  Future<void> openNew(TerminalGrid grid) => _run(() => workspace.openNew(grid));

  Future<void> attach(SessionInfo session, TerminalGrid grid) => _run(() => workspace.attach(session, grid));

  Future<void> close(TerminalTabController tab) => workspace.close(tab);

  /// "Mở phiên mới" on an ended tab: the new session takes the ended tab's place.
  Future<void> replaceWithNew(TerminalTabController ended, TerminalGrid grid) async {
    final opened = await _run(() => workspace.openNew(grid));
    if (opened != null) await workspace.close(ended);
  }

  void sendKey(ExtraKey key) {
    final tab = workspace.activeTab.peek();
    if (tab != null) workspace.extraKeys.sendKey(key, tab.terminal.peek());
  }

  /// Bracketed when the program enabled it, CR line breaks (spec §9.4).
  void paste(String text) {
    if (text.isEmpty) return;
    workspace.activeTab.peek()?.terminal.peek().paste(text);
  }

  void reconnectReplaced() => unawaited(_session.reconnectReplaced());

  void dismissNotice() {
    _noticeTimer?.cancel();
    if (!_disposed) _notice.value = null;
  }

  /// Runs a machine operation with the progress bar; failures become the notice.
  Future<T?> _run<T>(Future<T> Function() action) async {
    T? result;
    _busy.value = true;
    await guard(
      () async {
        try {
          result = await action();
        } catch (error) {
          await _handleFailure(error);
          rethrow;
        }
      },
      showError: false,
    );
    if (!_disposed) _busy.value = false;
    return result;
  }

  Future<void> _handleFailure(Object error) async {
    final failure = switch (error) {
      MachineFailed(:final failure) || MachineConnectionException(:final failure) => failure,
      _ => null,
    };
    if (failure == MachineConnectionFailure.untrusted) {
      // Spec §12: the machine no longer trusts this phone → drop the pinned key.
      _registry.remove(agentId);
      try {
        await _session.requireBackend.unpair(agentId);
      } on Object {
        // The pin is gone locally even if the relay call failed.
      }
      if (!_disposed) _exit.value = TerminalExit.untrusted;
      return;
    }
    if (failure == MachineConnectionFailure.protocolUnsupported) {
      if (!_disposed) _exit.value = TerminalExit.updateRequired;
      return;
    }
    _show(errorFactory.fromException(error).title);
  }

  void _show(String text) {
    if (_disposed) return;
    _noticeTimer?.cancel();
    _notice.value = text;
    _noticeTimer = Timer(noticeDuration, dismissNotice);
  }

  void dispose() {
    _disposed = true;
    _noticeTimer?.cancel();
    unawaited(_machineStates.cancel());
    unawaited(_relayStates.cancel());
    _canOpen.dispose();
    _fontSize.dispose();
    _busy.dispose();
    _notice.dispose();
    _exit.dispose();
    _machineState.dispose();
    _relayState.dispose();
  }
}
```

- [ ] **Step 6: Terminal page**

`apps/mobile/lib/features/terminal/presentation/pages/terminal_page.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/app/connection_banner.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_page_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_tab_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';
import 'package:shellx_mobile/features/terminal/presentation/terminal_metrics.dart';
import 'package:shellx_mobile/features/terminal/presentation/terminal_shortcuts.dart';
import 'package:shellx_mobile/features/terminal/presentation/widgets/extra_keys_bar.dart';
import 'package:shellx_mobile/features/terminal/presentation/widgets/pinch_zoom.dart';
import 'package:shellx_mobile/features/terminal/presentation/widgets/session_picker.dart';
import 'package:shellx_mobile/shared/shared.dart';
import 'package:xterm/xterm.dart';

/// Spec §9.2 #4 and the design's "Terminal" section: dark chrome bar (machine name, status line,
/// "Aa"), tab row, xterm, extra keys attached to the keyboard; in landscape the name and tabs
/// share one row next to a keyboard button. Pops with a [TerminalExit] when it must close.
@RoutePage()
class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key, required this.agentId, required this.machineName});

  final String agentId;
  final String machineName;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  late final TerminalPageController _controller = getIt<TerminalPageController>(param1: widget.agentId);
  late final void Function() _stopExit;
  final FocusNode _terminalFocus = FocusNode();
  TerminalGrid _grid = fallbackGrid;

  @override
  void initState() {
    super.initState();
    _stopExit = _controller.exit.subscribe((exit) {
      if (exit != null && mounted) context.router.maybePop(exit);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  @override
  void dispose() {
    _stopExit();
    _terminalFocus.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    final sessions = await _controller.prepare();
    if (sessions == null || !mounted) return;
    if (sessions.isEmpty) {
      if (_controller.workspace.tabs.peek().isEmpty) await _controller.openNew(_grid);
      return;
    }
    final choice = await showSessionPicker(context, sessions);
    switch (choice) {
      case AttachSession(:final session):
        await _controller.attach(session, _grid);
      case OpenNewSession():
        await _controller.openNew(_grid);
      case null:
        break;
    }
  }

  Future<void> _close(TerminalTabController tab) async {
    if (tab.isLive.peek()) {
      final strings = S.of(context);
      final confirmed = await showConfirmDialog(
        context,
        message: strings.terminalCloseConfirm,
        confirmLabel: strings.terminalCloseTab,
      );
      if (!confirmed) return;
    }
    await _controller.close(tab);
  }

  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text != null) _controller.paste(text);
  }

  Future<void> _copy(TerminalTabController tab) async {
    final range = tab.selection.selection;
    if (range == null) return;
    final copied = S.of(context).copied;
    await Clipboard.setData(ClipboardData(text: tab.terminal.peek().buffer.getText(range)));
    tab.selection.clearSelection();
    _controller.popupHandler.showSuccess(title: copied);
  }

  void _toggleKeyboard() {
    if (_terminalFocus.hasFocus) {
      _terminalFocus.unfocus();
    } else {
      _terminalFocus.requestFocus();
    }
  }

  Future<void> _showFontSize() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: context.colors.surface,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Watch((context) {
          final size = _controller.fontSize.value;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(S.of(context).fontSizeTooltip, style: context.typo.subHeader.bold)),
                  Text(size.toStringAsFixed(0), style: context.typo.subHeader),
                ],
              ),
              Row(
                children: [
                  Text('A', style: context.typo.metadata11.copyWith(color: context.colors.disable)),
                  Expanded(
                    child: Slider(
                      min: AppSettings.minFontSize,
                      max: AppSettings.maxFontSize,
                      divisions: (AppSettings.maxFontSize - AppSettings.minFontSize).round(),
                      value: size,
                      onChanged: _controller.setFontSize,
                    ),
                  ),
                  Text('A', style: context.typo.title.copyWith(color: context.colors.disable)),
                ],
              ),
            ],
          );
        }),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final workspace = _controller.workspace;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: TerminalColors.chrome,
        body: Column(
          children: [
            SafeArea(
              bottom: false,
              child: landscape
                  ? _ChromeBar(
                      onBack: () => context.router.maybePop(),
                      title: Text(
                        widget.machineName,
                        style: context.typo.paragraph.bold.copyWith(color: TerminalColors.title),
                      ),
                      middle: _TabStrip(
                        workspace: workspace,
                        canOpen: _controller.canOpen,
                        onOpen: () => _controller.openNew(_grid),
                        onClose: _close,
                        inline: true,
                      ),
                      trailing: IconButton(
                        tooltip: S.of(context).keyboardTooltip,
                        icon: const Icon(Icons.keyboard_outlined, color: TerminalColors.cyan),
                        onPressed: _toggleKeyboard,
                      ),
                    )
                  : Column(
                      children: [
                        _ChromeBar(
                          onBack: () => context.router.maybePop(),
                          title: _TitleBlock(name: widget.machineName, controller: _controller),
                          trailing: IconButton(
                            tooltip: S.of(context).fontSizeTooltip,
                            onPressed: _showFontSize,
                            icon: Text(
                              'Aa',
                              style: context.typo.subHeader15.bold.copyWith(color: TerminalColors.cyan),
                            ),
                          ),
                        ),
                        _TabStrip(
                          workspace: workspace,
                          canOpen: _controller.canOpen,
                          onOpen: () => _controller.openNew(_grid),
                          onClose: _close,
                        ),
                      ],
                    ),
            ),
            ConnectionBanner(
              backend: _controller.backend,
              onReconnectReplaced: _controller.reconnectReplaced,
              showReconnecting: false,
            ),
            Watch(
              (context) =>
                  _controller.busy.value ? const LinearProgressIndicator(minHeight: 2) : const SizedBox(height: 2),
            ),
            Expanded(
              child: ColoredBox(
                color: TerminalColors.background,
                child: LayoutBuilder(
                  builder: (context, constraints) => Watch((context) {
                    final fontSize = _controller.fontSize.value;
                    _grid =
                        measureTerminalGrid(
                          constraints.biggest,
                          shellxTerminalStyle(fontSize),
                          MediaQuery.textScalerOf(context),
                        ) ??
                        fallbackGrid;
                    final active = workspace.activeTab.value;
                    final notice = _controller.notice.value;
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: active == null
                              ? _NoTab(busy: _controller.busy.value, onOpen: () => _controller.openNew(_grid))
                              : _TerminalPane(
                                  key: ValueKey(active.id),
                                  tab: active,
                                  focusNode: _terminalFocus,
                                  fontSize: fontSize,
                                  onFontSize: _controller.setFontSize,
                                  onCopy: () => _copy(active),
                                  onCloseTab: () => _controller.close(active),
                                  onOpenNew: () => _controller.replaceWithNew(active, _grid),
                                ),
                        ),
                        if (notice != null)
                          Positioned(
                            top: 8,
                            left: 12,
                            right: 12,
                            child: _FloatingNotice(text: notice, onTap: _controller.dismissNotice),
                          ),
                      ],
                    );
                  }),
                ),
              ),
            ),
            Container(
              color: context.colors.keyboardBackground,
              child: SafeArea(
                top: false,
                child: ExtraKeysBar(controller: workspace.extraKeys, onKey: _controller.sendKey, onPaste: _paste),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The dark bar above the tabs (`.tbar`).
class _ChromeBar extends StatelessWidget {
  const _ChromeBar({required this.onBack, required this.title, required this.trailing, this.middle});

  final VoidCallback onBack;
  final Widget title;
  final Widget? middle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: Row(
        children: [
          IconButton(
            tooltip: S.of(context).backToMachines,
            icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: TerminalColors.cyan),
            onPressed: onBack,
          ),
          if (middle == null)
            Expanded(child: title)
          else ...[
            title,
            const SizedBox(width: 10),
            Expanded(child: middle!),
          ],
          trailing,
        ],
      ),
    );
  }
}

/// Machine name and the status line ("Đã kết nối · mã hóa đầu cuối").
class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.name, required this.controller});

  final String name;
  final TerminalPageController controller;

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    return Watch((context) {
      final relay = controller.relayState.value;
      final reconnecting = relay == RelayConnectionState.disconnected;
      final ready = controller.machineState.value is MachineReady && !reconnecting;
      final status = reconnecting
          ? strings.bannerReconnecting
          : ready
          ? strings.terminalConnected
          : strings.terminalConnecting;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.typo.subHeader15.bold.copyWith(color: TerminalColors.title),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: ready ? context.colors.okDot : TerminalColors.dim,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.typo.metadata12.copyWith(color: TerminalColors.dim, height: 1.3),
                ),
              ),
            ],
          ),
        ],
      );
    });
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.workspace,
    required this.canOpen,
    required this.onOpen,
    required this.onClose,
    this.inline = false,
  });

  final TerminalWorkspace workspace;
  final ReadonlySignal<bool> canOpen;
  final VoidCallback onOpen;
  final ValueChanged<TerminalTabController> onClose;

  /// Landscape: part of the chrome bar instead of its own row.
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    return Watch((context) {
      final tabs = workspace.tabs.value;
      final activeIndex = workspace.activeIndex.value;
      return Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: inline
            ? null
            : const BoxDecoration(
                color: TerminalColors.chrome,
                border: Border(bottom: BorderSide(color: TerminalColors.line)),
              ),
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final (index, tab) in tabs.indexed)
              _TabChip(
                key: ValueKey('tab-${tab.id}'),
                tab: tab,
                selected: index == activeIndex,
                onSelect: () => workspace.select(index),
                onClose: () => onClose(tab),
                closeTooltip: strings.terminalCloseTab,
              ),
            IconButton(
              tooltip: strings.terminalOpenNew,
              icon: const Icon(Icons.add, size: 20, color: TerminalColors.cyan),
              onPressed: canOpen.value ? onOpen : null,
            ),
          ],
        ),
      );
    });
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    super.key,
    required this.tab,
    required this.selected,
    required this.onSelect,
    required this.onClose,
    required this.closeTooltip,
  });

  final TerminalTabController tab;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final String closeTooltip;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final live = tab.isLive.value;
      return Padding(
        padding: const EdgeInsets.only(top: 5, right: 2),
        child: Material(
          color: selected ? TerminalColors.background : Colors.transparent,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          child: InkWell(
            onTap: onSelect,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: live ? TerminalColors.green : TerminalColors.dim,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    tab.title.value,
                    style: TextStyle(
                      fontFamily: FontFamily.jetBrainsMono,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? const Color(0xFFEAF3F5) : TerminalColors.dim,
                    ),
                  ),
                  Tooltip(
                    message: closeTooltip,
                    child: InkWell(
                      onTap: onClose,
                      child: const SizedBox(
                        width: 36,
                        height: 39,
                        child: Icon(Icons.close, size: 14, color: TerminalColors.dim),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// No tab yet: the session list is loading, or every tab was closed.
class _NoTab extends StatelessWidget {
  const _NoTab({required this.busy, required this.onOpen});

  final bool busy;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final dim = context.typo.paragraph.copyWith(color: TerminalColors.dim);
    if (busy) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(strings.sessionsLoading, style: dim),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(strings.terminalNoTabs, style: dim),
          12.sizedHeight,
          AppButton(
            title: strings.terminalOpenNew,
            height: 44,
            backgroundColor: TerminalColors.cyan,
            textColor: TerminalColors.onCyan,
            onTap: onOpen,
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
    required this.focusNode,
    required this.fontSize,
    required this.onFontSize,
    required this.onCopy,
    required this.onCloseTab,
    required this.onOpenNew,
  });

  final TerminalTabController tab;
  final FocusNode focusNode;
  final double fontSize;
  final ValueChanged<double> onFontSize;
  final VoidCallback onCopy;
  final VoidCallback onCloseTab;
  final VoidCallback onOpenNew;

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    return Watch((context) {
      final banner = tab.banner.value;
      return Stack(
        children: [
          Positioned.fill(
            child: PinchToZoom(
              fontSize: fontSize,
              onFontSize: onFontSize,
              child: TerminalView(
                tab.terminal.value,
                controller: tab.selection,
                focusNode: focusNode,
                theme: TerminalColors.theme,
                textStyle: shellxTerminalStyle(fontSize),
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                autofocus: true,
                deleteDetection: true,
                readOnly: !tab.isLive.value,
                shortcuts: terminalShortcuts(defaultTargetPlatform),
              ),
            ),
          ),
          // Every child is positioned, so the stack fills the pane.
          Positioned(
            top: 8,
            right: 8,
            child: ListenableBuilder(
              listenable: tab.selection,
              builder: (context, _) => tab.selection.selection == null
                  ? const SizedBox.shrink()
                  : FilledButton.tonalIcon(
                      onPressed: onCopy,
                      icon: const Icon(Icons.copy, size: 16),
                      label: Text(strings.copyAction),
                    ),
            ),
          ),
          if (banner != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: _EndedCard(banner: banner, onCloseTab: onCloseTab, onOpenNew: onOpenNew, onReattach: tab.reattach),
            ),
        ],
      );
    });
  }
}

/// Design "Phiên đã kết thúc": the tab keeps its content; the card offers the next step.
class _EndedCard extends StatelessWidget {
  const _EndedCard({required this.banner, required this.onCloseTab, required this.onOpenNew, required this.onReattach});

  final TabBanner banner;
  final VoidCallback onCloseTab;
  final VoidCallback onOpenNew;
  final VoidCallback onReattach;

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final (title, body) = switch (banner.notice) {
      TabNotice.exited => (strings.sessionEnded, strings.sessionExitedBody(banner.exitCode ?? 0)),
      TabNotice.sessionEnded => (strings.sessionEnded, strings.sessionGoneBody),
      TabNotice.takenOver => (strings.tabTakenOver, null),
      TabNotice.closedByHost => (strings.tabClosedByHost, null),
      TabNotice.failed => (ErrorText(strings).appError(banner.errorCode!, banner.detail ?? ''), null),
    };
    final takenOver = banner.notice == TabNotice.takenOver;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TerminalColors.chrome2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TerminalColors.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: context.typo.subHeader15.bold.copyWith(color: Colors.white)),
          if (body != null) ...[
            4.sizedHeight,
            Text(body, style: context.typo.paragraph13.copyWith(color: TerminalColors.dim)),
          ],
          10.sizedHeight,
          Row(
            children: [
              Expanded(
                child: AppButton(
                  title: strings.closeTab,
                  height: 44,
                  radius: 11,
                  backgroundColor: TerminalColors.secondaryAction,
                  textColor: const Color(0xFFE6F0F2),
                  onTap: onCloseTab,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  title: takenOver ? strings.tabReattach : strings.terminalOpenNew,
                  height: 44,
                  radius: 11,
                  backgroundColor: TerminalColors.cyan,
                  textColor: TerminalColors.onCyan,
                  onTap: takenOver ? onReattach : onOpenNew,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Design "session_limit": a floating notice over the terminal.
class _FloatingNotice extends StatelessWidget {
  const _FloatingNotice({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: TerminalColors.noticeBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: TerminalColors.noticeBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 20, color: TerminalColors.red),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: context.typo.paragraph13.bold.copyWith(color: TerminalColors.noticeText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Generate, run the tests, analyze**

```bash
cd apps/mobile
dart run build_runner build
flutter test test/features/terminal/terminal_page_test.dart
flutter analyze
flutter test
```

Expected: `build_runner` adds `TerminalRoute` and the `TerminalPageController` factory; `+15: All tests passed!`; `No issues found!`; `+279: All tests passed!`.

- [ ] **Step 8: Commit**

```bash
git add apps/mobile
git commit -m "feat(mobile): terminal page with tabs, session sheet, extra keys, copy/paste and notices"
```

---

### Task 15: QR pairing — parse, pair, spec messages, scanner page

UI per the design's "Quét QR" screens (binding): a full-screen camera with a round close button, the title "Quét mã ghép nối", a square frame with corner marks and a moving scan line (still when the system asks for reduced motion), and a card "Mã nằm trên máy tính của bạn" that says where the code is on macOS and Windows with the menu item "Ghép nối điện thoại…" as a key chip. While pairing: "Đang ghép nối…". Failure: a bottom sheet "Không ghép nối được" with the spec §12 text, "Quét lại" and "Đóng" (scans are ignored until "Quét lại"). Success: "Đã ghép nối", "{name} đã tin cậy điện thoại này…", "Mở terminal" (replaces the scanner with that machine's terminal) and "Về danh sách máy" (pops with the agent id). Camera denied: the text and "Mở Cài đặt".

**Files:**
- Create: `apps/mobile/lib/features/pairing/domain/pairing_flow.dart`
- Create: `apps/mobile/lib/features/pairing/presentation/controllers/qr_scanner_controller.dart`
- Create: `apps/mobile/lib/features/pairing/presentation/pages/qr_scanner_page.dart`
- Test: `apps/mobile/test/features/pairing/pairing_test.dart`

**Interfaces:**
- Consumes: `PairingUri.parse` (`FormatException`), `PairingUri(...).toUriString()`, `ApiException` (`shellx_core`); `PairingException`, `PairingFailure` (`shellx_client`); `ShellxBackend.pair/devices` (Task 10); `SessionHolder.requireBackend` (Task 11); `ErrorText` (Task 9); `ExternalLinks.openAppSettings` (Task 3); `MobileScanner`, `MobileScannerController`, `BarcodeFormat`, `DetectionSpeed`, `MobileScannerErrorCode` (`mobile_scanner` 7.4.2); `TerminalRoute` (Task 14).
- Produces:
  - `sealed class PairingOutcome`, `final class PairingSucceeded extends PairingOutcome { const PairingSucceeded(String agentId); }`, `final class PairingRejected extends PairingOutcome { const PairingRejected(String message); }`, `Future<PairingOutcome> pairFromQrCode(String raw, ShellxBackend backend, ErrorText text)`
  - `sealed class ScannerStep` with `Scanning()`, `Pairing()`, `PairingFailed(String message)`, `Paired({required String agentId, required String machineName})`; `@injectable class QrScannerController extends Controller { QrScannerController(SessionHolder session); ReadonlySignal<ScannerStep> get step; Future<void> onCode(String raw, S strings); void scanAgain(); void dispose(); }`
  - `typedef ScannerViewBuilder = Widget Function(BuildContext context, ValueChanged<String> onCode);`, `Widget cameraScannerView(BuildContext context, ValueChanged<String> onCode)`, `@RoutePage() class QrScannerPage extends StatefulWidget { const QrScannerPage({Key? key, ScannerViewBuilder scannerBuilder = cameraScannerView}); }` → `QrScannerRoute(scannerBuilder:)`; pops with the paired agent id.

A QR code that is not a `shellx://pair?...` URI gets the "invalid or expired" text. Detection is ignored while pairing runs or while a failure is shown; "Quét lại" re-arms it. The machine's name for the success screen comes from `GET /v1/devices` (fallback "Máy không xác định").

- [ ] **Step 1: Write the failing tests**

`apps/mobile/test/features/pairing/pairing_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/pairing/domain/pairing_flow.dart';
import 'package:shellx_mobile/features/pairing/presentation/controllers/qr_scanner_controller.dart';
import 'package:shellx_mobile/shared/shared.dart';

import '../../support/app_harness.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fakes.dart';

void main() {
  final validCode = PairingUri(
    agentDeviceId: agentA,
    agentPublicKey: Uint8List(32)..fillRange(0, 32, 7),
    secret: Uint8List(32)..fillRange(0, 32, 9),
  ).toUriString();
  late FakeBackend backend;

  setUp(() => backend = FakeBackend());

  group('pairFromQrCode', () {
    late ErrorText text;
    setUp(() async => text = ErrorText(await S.load(vi)));

    test('pairs with the scanned machine', () async {
      final outcome = await pairFromQrCode(validCode, backend, text);
      expect(outcome, isA<PairingSucceeded>().having((o) => o.agentId, 'agentId', agentA));
      expect(backend.paired.single.agentDeviceId, agentA);
    });

    test('a QR code that is not a pairing URI is "invalid or expired"', () async {
      final outcome = await pairFromQrCode('https://example.com', backend, text);
      expect(
        (outcome as PairingRejected).message,
        'Mã QR không hợp lệ hoặc đã hết hạn. Hãy tạo mã mới trên máy tính.',
      );
      expect(backend.paired, isEmpty);
    });

    final cases = {
      PairingFailure.notInAccount: 'Máy này không thuộc tài khoản của bạn. Hãy đăng nhập cùng tài khoản trên máy tính.',
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

  group('QrScannerPage', () {
    late ValueChanged<String> scan;
    late List<Object?> results;
    late List<Object?> terminals;

    setUp(() {
      backend.deviceList = [agentDevice(agentA, 'MacBook Pro của Phú')];
      results = [];
      terminals = [];
      final session = FakeSessionHolder(backend);
      getIt
        ..registerSingleton<PopupHandler>(FakePopupHandler())
        ..registerFactory<QrScannerController>(() => QrScannerController(session));
    });

    tearDown(getIt.reset);

    Future<void> openScanner(WidgetTester tester) async {
      // Reduced motion stops the scan line, so pumpAndSettle can settle.
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pumpWidget(
        routedApp(
          open: () => QrScannerRoute(
            scannerBuilder: (context, onCode) {
              scan = onCode;
              return const ColoredBox(color: Colors.black);
            },
          ),
          routes: [
            AutoRoute(page: QrScannerRoute.page),
            stubRoute(TerminalRoute.name, pushed: terminals),
          ],
          results: results,
        ),
      );
      await tester.pumpAndSettle();
      await openPushed(tester);
    }

    testWidgets('the camera card says where the code is', (tester) async {
      await openScanner(tester);
      expect(find.text('Quét mã ghép nối'), findsOneWidget);
      expect(find.text('Mã nằm trên máy tính của bạn'), findsOneWidget);
      expect(find.text('Ghép nối điện thoại…'), findsOneWidget);
      await tester.tap(find.byTooltip('Đóng'));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('success: "Đã ghép nối" with the machine; "Về danh sách máy" returns it', (tester) async {
      await openScanner(tester);
      scan(validCode);
      await tester.pumpAndSettle();
      expect(find.text('Đã ghép nối'), findsOneWidget);
      expect(find.textContaining('MacBook Pro của Phú đã tin cậy điện thoại này.'), findsOneWidget);

      await tester.tap(find.text('Về danh sách máy'));
      await tester.pumpAndSettle();
      expect(results, [agentA]);
    });

    testWidgets('success: "Mở terminal" opens the new machine', (tester) async {
      await openScanner(tester);
      scan(validCode);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mở terminal'));
      await tester.pumpAndSettle();
      final args = terminals.single as TerminalRouteArgs;
      expect((args.agentId, args.machineName), (agentA, 'MacBook Pro của Phú'));
    });

    testWidgets('a failure shows the sheet; scans wait for "Quét lại"; "Đóng" leaves', (tester) async {
      backend.pairError = const PairingException(PairingFailure.notInAccount);
      await openScanner(tester);

      scan(validCode);
      await tester.pumpAndSettle();
      expect(find.text('Không ghép nối được'), findsOneWidget);
      expect(
        find.text('Máy này không thuộc tài khoản của bạn. Hãy đăng nhập cùng tài khoản trên máy tính.'),
        findsOneWidget,
      );

      scan(validCode); // ignored while the sheet is shown
      await tester.pumpAndSettle();
      expect(backend.paired, isEmpty);

      await tester.tap(find.text('Quét lại'));
      await tester.pumpAndSettle();
      backend.pairError = null;
      scan(validCode);
      await tester.pumpAndSettle();
      expect(backend.paired, hasLength(1));
    });

    testWidgets('"Đóng" on the failure sheet closes the scanner', (tester) async {
      await openScanner(tester);
      scan('https://example.com');
      await tester.pumpAndSettle();
      expect(find.text('Mã QR không hợp lệ hoặc đã hết hạn. Hãy tạo mã mới trên máy tính.'), findsOneWidget);
      await tester.tap(find.widgetWithText(AppButton, 'Đóng'));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd apps/mobile && flutter test test/features/pairing/pairing_test.dart`
Expected: FAIL — `Error when reading 'lib/features/pairing/domain/pairing_flow.dart': No such file or directory` (and `QrScannerRoute` is not defined).

- [ ] **Step 3: Implement**

`apps/mobile/lib/features/pairing/domain/pairing_flow.dart`:

```dart
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';

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

`apps/mobile/lib/features/pairing/presentation/controllers/qr_scanner_controller.dart`:

```dart
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/pairing/domain/pairing_flow.dart';
import 'package:shellx_mobile/shared/shared.dart';

sealed class ScannerStep {
  const ScannerStep();
}

final class Scanning extends ScannerStep {
  const Scanning();
}

final class Pairing extends ScannerStep {
  const Pairing();
}

/// Design "Mã sai hoặc hết hạn": the sheet with the spec §5.3/§12 message.
final class PairingFailed extends ScannerStep {
  const PairingFailed(this.message);
  final String message;
}

/// Design "Ghép nối xong".
final class Paired extends ScannerStep {
  const Paired({required this.agentId, required this.machineName});
  final String agentId;
  final String machineName;
}

/// Spec §9.2 #3: one scan at a time; a failure stays on screen until "Quét lại".
@injectable
class QrScannerController extends Controller {
  QrScannerController(this._session);

  final SessionHolder _session;
  final Signal<ScannerStep> _step = signal(const Scanning());
  bool _disposed = false;

  ReadonlySignal<ScannerStep> get step => _step;

  /// Pairs with the scanned machine; codes seen while pairing or while a result is shown are
  /// ignored.
  Future<void> onCode(String raw, S strings) async {
    if (_step.peek() is! Scanning) return;
    _step.value = const Pairing();
    final backend = _session.requireBackend;
    final outcome = await pairFromQrCode(raw, backend, ErrorText(strings));
    if (_disposed) return;
    switch (outcome) {
      case PairingSucceeded(:final agentId):
        _step.value = Paired(agentId: agentId, machineName: await _nameOf(agentId, strings));
      case PairingRejected(:final message):
        _step.value = PairingFailed(message);
    }
  }

  Future<String> _nameOf(String agentId, S strings) async {
    try {
      for (final device in await _session.requireBackend.devices()) {
        if (device.id == agentId) return device.name;
      }
    } on Object {
      // Offline right after pairing: the list shows the name later.
    }
    return strings.unknownMachine;
  }

  void scanAgain() => _step.value = const Scanning();

  void dispose() {
    _disposed = true;
    _step.dispose();
  }
}
```

`apps/mobile/lib/features/pairing/presentation/pages/qr_scanner_page.dart`:

```dart
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/pairing/presentation/controllers/qr_scanner_controller.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Builds the camera view; tests replace it with a fake scanner.
typedef ScannerViewBuilder = Widget Function(BuildContext context, ValueChanged<String> onCode);

Widget cameraScannerView(BuildContext context, ValueChanged<String> onCode) => _CameraScanner(onCode: onCode);

/// Spec §9.2 #3 and the design's "Ghép nối bằng mã QR": camera with a framed target and a card
/// saying where the code is; a failure sheet with "Quét lại"; a success screen with
/// "Mở terminal" / "Về danh sách máy".
@RoutePage()
class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key, this.scannerBuilder = cameraScannerView});

  final ScannerViewBuilder scannerBuilder;

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final QrScannerController _controller = getIt<QrScannerController>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onCode(String raw) => _controller.onCode(raw, S.of(context));

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final step = _controller.step.value;
      if (step is Paired) return _PairedView(step: step);
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: const Color(0xFF05090A),
          body: Stack(
            fit: StackFit.expand,
            children: [
              widget.scannerBuilder(context, _onCode),
              const _ScanFrame(),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _RoundButton(
                          tooltip: S.of(context).actionClose,
                          icon: Icons.close,
                          onTap: () => context.router.maybePop(),
                        ),
                      ),
                    ),
                    Text(
                      S.of(context).scannerTitle,
                      style: context.typo.heading20.heavy.copyWith(color: Colors.white),
                    ),
                    const Spacer(),
                    const _WhereIsTheCode(),
                  ],
                ),
              ),
              if (step is Pairing) const _PairingOverlay(),
              if (step is PairingFailed) _FailureSheet(message: step.message, onScanAgain: _controller.scanAgain),
            ],
          ),
        ),
      );
    });
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.tooltip, required this.icon, required this.onTap});

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0x24FFFFFF),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(dimension: 44, child: Icon(icon, color: Colors.white)),
        ),
      ),
    );
  }
}

/// The 250 pt target with rounded corners and the moving cyan scan line.
class _ScanFrame extends StatefulWidget {
  const _ScanFrame();

  @override
  State<_ScanFrame> createState() => _ScanFrameState();
}

class _ScanFrameState extends State<_ScanFrame> with SingleTickerProviderStateMixin {
  late final AnimationController _line = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The design's `prefers-reduced-motion`: a still line when the system asks for less motion.
    if (MediaQuery.disableAnimationsOf(context)) {
      _line.stop();
    } else if (!_line.isAnimating) {
      _line.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _line.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox.square(
        dimension: 250,
        child: Stack(
          children: [
            const Positioned.fill(child: CustomPaint(painter: _CornersPainter())),
            AnimatedBuilder(
              animation: _line,
              builder: (context, _) => Positioned(
                left: 14,
                right: 14,
                top: 14 + 216 * _line.value,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: TerminalColors.cyan,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: const [BoxShadow(color: TerminalColors.cyan, blurRadius: 14)],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CornersPainter extends CustomPainter {
  const _CornersPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const arm = 46.0;
    const radius = 22.0;
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final w = size.width;
    final h = size.height;
    for (final (corner, dx, dy) in [
      (Offset.zero, 1.0, 1.0),
      (Offset(w, 0), -1.0, 1.0),
      (Offset(0, h), 1.0, -1.0),
      (Offset(w, h), -1.0, -1.0),
    ]) {
      final path = Path()
        ..moveTo(corner.dx, corner.dy + dy * arm)
        ..lineTo(corner.dx, corner.dy + dy * radius)
        ..quadraticBezierTo(corner.dx, corner.dy, corner.dx + dx * radius, corner.dy)
        ..lineTo(corner.dx + dx * arm, corner.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// "Mã nằm trên máy tính của bạn" and where to find it on macOS and Windows.
class _WhereIsTheCode extends StatelessWidget {
  const _WhereIsTheCode();

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final menu = strings.pairPhoneMenuItem;
    final body = strings.scannerCardBody(menu).split(menu);
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 20),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xDB10181B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.scannerCardTitle, style: context.typo.subHeader15.bold.copyWith(color: Colors.white)),
          8.sizedHeight,
          Text.rich(
            TextSpan(
              style: context.typo.paragraph.copyWith(color: const Color(0xFFDFE8EA)),
              children: [
                TextSpan(text: body.first),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: const Color(0x1FFFFFFF), borderRadius: BorderRadius.circular(5)),
                    child: Text(
                      menu,
                      style: const TextStyle(fontFamily: FontFamily.jetBrainsMono, fontSize: 12.5, color: Colors.white),
                    ),
                  ),
                ),
                if (body.length > 1) TextSpan(text: body.last),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PairingOverlay extends StatelessWidget {
  const _PairingOverlay();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            12.sizedHeight,
            Text(S.of(context).scannerPairing, style: context.typo.subHeader.copyWith(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

/// Design "Mã sai hoặc hết hạn": the camera blurs behind a sheet with the spec message.
class _FailureSheet extends StatelessWidget {
  const _FailureSheet({required this.message, required this.onScanAgain});

  final String message;
  final VoidCallback onScanAgain;

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final colors = context.colors;
    return Stack(
      children: [
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
            child: ColoredBox(color: colors.scrim),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(color: colors.border, borderRadius: BorderRadius.circular(3)),
                  ),
                  14.sizedHeight,
                  const StatusCircle(icon: Icons.warning_amber_rounded, tone: StatusTone.error),
                  14.sizedHeight,
                  Text(strings.pairingFailedTitle, style: context.typo.heading20.heavy),
                  8.sizedHeight,
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: context.typo.subHeader15.copyWith(color: colors.secondaryText),
                  ),
                  16.sizedHeight,
                  AppButton(title: strings.scanAgain, width: double.infinity, onTap: onScanAgain),
                  4.sizedHeight,
                  AppButton(
                    title: strings.actionClose,
                    width: double.infinity,
                    height: 44,
                    backgroundColor: Colors.transparent,
                    textColor: colors.primary,
                    onTap: () => context.router.maybePop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Design "Ghép nối xong".
class _PairedView extends StatelessWidget {
  const _PairedView({required this.step});

  final Paired step;

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            children: [
              const Spacer(),
              const StatusCircle(icon: Icons.check),
              16.sizedHeight,
              Text(strings.pairingSucceeded, style: context.typo.heading26.heavy),
              12.sizedHeight,
              HighlightedText(
                strings.pairingSucceededBody(step.machineName),
                parts: {step.machineName: null},
                textAlign: TextAlign.center,
                style: context.typo.subHeader15.copyWith(color: colors.secondaryText),
                partStyle: context.typo.subHeader15.bold.copyWith(color: colors.primaryText),
              ),
              const Spacer(),
              AppButton(
                title: strings.openTerminal,
                width: double.infinity,
                onTap: () =>
                    context.router.replace(TerminalRoute(agentId: step.agentId, machineName: step.machineName)),
              ),
              4.sizedHeight,
              AppButton(
                title: strings.backToMachines,
                width: double.infinity,
                backgroundColor: Colors.transparent,
                textColor: colors.primary,
                onTap: () => context.router.maybePop(step.agentId),
              ),
            ],
          ),
        ),
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
  final MobileScannerController _scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    return MobileScanner(
      controller: _scanner,
      onDetect: (capture) {
        final raw = capture.barcodes.firstOrNull?.rawValue;
        if (raw != null) widget.onCode(raw);
      },
      errorBuilder: (context, error) {
        final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
        return ColoredBox(
          color: Colors.black,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    denied ? strings.scannerCameraDenied : strings.scannerCameraError,
                    textAlign: TextAlign.center,
                    style: context.typo.subHeader.copyWith(color: Colors.white),
                  ),
                  if (denied) ...[
                    16.sizedHeight,
                    AppButton(title: strings.openSettings, onTap: () => getIt<ExternalLinks>().openAppSettings()),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Generate, run the tests, analyze**

```bash
cd apps/mobile
dart run build_runner build
flutter test test/features/pairing/pairing_test.dart
flutter analyze
flutter test
```

Expected: `+13: All tests passed!`; `No issues found!`; `+292: All tests passed!`.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile
git commit -m "feat(mobile): QR pairing with spec messages and the designed scanner page"
```

---

### Task 16: Settings and account deletion

UI per the design's "Cài đặt" and "Xóa tài khoản" screens (binding). Settings, as grouped cards: **Terminal** — "Cỡ chữ mặc định" with a slider (8–32) and a live JetBrains Mono preview; **Bảo mật** — "Khóa bằng {method}" switch (on by default, disabled with "Thiết bị chưa đặt mã khóa hoặc sinh trắc học" when the device has neither) and the footnote "Hỏi khi mở app và khi quay lại sau hơn 5 phút."; **Máy đã ghép nối** — one row per machine with "Bỏ ghép nối" (confirmation; spec §5.5); **Tài khoản** — the email, "Đăng xuất" (confirmation; only the token is deleted — Task 11) and a red "Xóa tài khoản"; a footer "ShellX {version} ({build})" that opens the licences page. Delete account: the warning box "Không hoàn tác được" with three bullets (account + devices + pairings, computers signed out, open sessions closed), "Nhập mật khẩu để xác nhận", "Mật khẩu không đúng." under the field on `invalid_credentials`, a red "Xóa vĩnh viễn" button that stays dimmed until a password is typed, and "Hủy".

**Files:**
- Create: `apps/mobile/lib/features/settings/presentation/controllers/settings_controller.dart`, `delete_account_controller.dart`
- Create: `apps/mobile/lib/features/settings/presentation/pages/settings_page.dart`, `delete_account_page.dart`
- Test: `apps/mobile/test/features/settings/settings_page_test.dart`

**Interfaces:**
- Consumes: `AppSettings` (Task 3); `AppLockController.kind/settingChanged`, `BiometricAuthenticator.isAvailable`, `biometricMethod` (Task 4); `SessionHolder` (`session`, `logout`, `deleteAccount`, `requireBackend`) (Task 11); `ShellxBackend.pinnedMachines/devices/unpair` (Task 10); `WorkspaceRegistry.remove` (Task 13); `ErrorText`/`errorFactory` (Task 9); `PackageInfo`; `showLicensePage`; `showConfirmDialog`, `AppButton`, `PasswordTextField` (Task 2).
- Produces:
  - `typedef PairedMachine = ({String agentId, String? name});`, `@injectable class SettingsController extends Controller { SettingsController(SessionHolder, AppSettings settings, AppLockController, BiometricAuthenticator, WorkspaceRegistry, PackageInfo); String get email; String get version; String get buildNumber; ReadonlySignal<BiometricKind> get lockKind; ReadonlySignal<bool> get biometricsAvailable; ReadonlySignal<List<PairedMachine>?> get paired; Future<void> load(); Future<void> setFontSize(double); Future<void> setBiometricLock(bool); Future<void> unpair(String agentId); Future<void> logout(); void dispose(); }`
  - `@injectable class DeleteAccountController extends Controller { DeleteAccountController(SessionHolder); ReadonlySignal<bool> get busy; ReadonlySignal<String?> get error; String get email; void clearError(); Future<void> delete(String password); void dispose(); }` — the failure is shown under the password field: "Mật khẩu không đúng." for `invalid_credentials`, the `ErrorText` text otherwise (e.g. "Thử lại sau ít phút." for 429).
  - `@RoutePage() SettingsPage` → `SettingsRoute()`, `@RoutePage() DeleteAccountPage` → `DeleteAccountRoute()`.

Signing out and deleting the account end in a `SignedOutEvent`; Task 19's `SessionEnforcer` then replaces the stack with the login page (the pages do not navigate there themselves).

- [ ] **Step 1: Write the failing widget tests**

`apps/mobile/test/features/settings/settings_page_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/lock/presentation/app_lock_controller.dart';
import 'package:shellx_mobile/features/settings/presentation/controllers/delete_account_controller.dart';
import 'package:shellx_mobile/features/settings/presentation/controllers/settings_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';
import 'package:shellx_mobile/shared/shared.dart';

import '../../support/app_harness.dart';
import '../../support/fake_biometrics.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fakes.dart';

void main() {
  late AppSettings settings;
  late FakeBiometricAuthenticator biometrics;
  late AppLockController lock;
  late FakeBackend backend;
  late FakeSessionHolder session;
  late WorkspaceRegistry registry;
  late FakePopupHandler popups;

  setUp(() async {
    settings = AppSettings(InMemoryKeyValueStore());
    await settings.load();
    biometrics = FakeBiometricAuthenticator();
    lock = AppLockController(authenticator: biometrics, isEnabled: () => settings.biometricLock.peek());
    await lock.detectKind();
    backend = FakeBackend(
      devices: [agentDevice(agentA, 'MacBook-Pro'), agentDevice(agentB, 'DESKTOP-42')],
      pinnedList: [pinned(agentA)],
    )..addMachine(agentA);
    session = FakeSessionHolder(backend);
    registry = WorkspaceRegistry(session.backend);
    popups = FakePopupHandler();
    getIt
      ..registerSingleton<PopupHandler>(popups)
      ..registerFactory<SettingsController>(
        () => SettingsController(
          session,
          settings,
          lock,
          biometrics,
          registry,
          PackageInfo(appName: 'ShellX', packageName: 'pro.shellx.mobile', version: '1.0.0', buildNumber: '1'),
        ),
      )
      ..registerFactory<DeleteAccountController>(() => DeleteAccountController(session));
  });

  tearDown(() async {
    registry.dispose();
    await getIt.reset();
  });

  Future<void> openSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      routedApp(
        open: () => const SettingsRoute(),
        routes: [
          AutoRoute(page: SettingsRoute.page),
          AutoRoute(page: DeleteAccountRoute.page),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await openPushed(tester);
  }

  testWidgets('design: grouped cards, account email, version footer, paired machines by name', (tester) async {
    await openSettings(tester);
    for (final header in ['TERMINAL', 'BẢO MẬT', 'MÁY ĐÃ GHÉP NỐI', 'TÀI KHOẢN']) {
      expect(find.text(header), findsOneWidget, reason: header);
    }
    expect(find.text('me@example.com'), findsOneWidget);
    expect(find.text('ShellX 1.0.0 (1)'), findsOneWidget);
    expect(find.text('MacBook-Pro'), findsOneWidget);
    expect(find.text('DESKTOP-42'), findsNothing); // not paired
    expect(find.text('user@macbook'), findsNothing); // the preview is one rich text
    expect(find.textContaining('user@macbook', findRichText: true), findsOneWidget);
  });

  testWidgets('font size slider persists the default size', (tester) async {
    await openSettings(tester);
    tester.widget<Slider>(find.byType(Slider)).onChanged!(20);
    await tester.pump();
    expect(settings.fontSize.value, 20);
    expect(find.text('20'), findsWidgets);
  });

  testWidgets('biometric switch is on by default and can be turned off', (tester) async {
    lock.lockOnLaunch();
    await openSettings(tester);
    expect(find.text('Khóa bằng Face ID'), findsOneWidget);
    expect(find.text('Hỏi khi mở app và khi quay lại sau hơn 5 phút.'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(settings.biometricLock.value, isFalse);
    expect(lock.isLocked.value, isFalse);
  });

  testWidgets('biometric switch is disabled without passcode or biometrics', (tester) async {
    biometrics.available = false;
    await openSettings(tester);
    expect(find.text('Thiết bị chưa đặt mã khóa hoặc sinh trắc học'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged, isNull);
  });

  testWidgets('unpair asks, unpairs, drops the tabs and refreshes the list (spec §5.5)', (tester) async {
    registry.forMachine(agentA);
    await openSettings(tester);
    await tester.tap(find.text('Bỏ ghép nối'));
    await tester.pumpAndSettle();
    expect(find.text('Bỏ ghép nối MacBook-Pro? Bạn sẽ phải quét lại mã QR để dùng máy này.'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Bỏ ghép nối').last);
    await tester.pumpAndSettle();
    expect(backend.unpaired, [agentA]);
    expect(() => registry.forMachine(agentA), throwsStateError); // the old workspace is gone
    expect(find.text('Chưa ghép nối máy nào.'), findsOneWidget);
  });

  testWidgets('sign out asks for confirmation', (tester) async {
    await openSettings(tester);
    await tester.tap(find.text('Đăng xuất'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(session.logoutCalls, 0);
    await tester.tap(find.text('Đăng xuất'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Đăng xuất'));
    await tester.pumpAndSettle();
    expect(session.logoutCalls, 1);
  });

  group('delete account', () {
    Future<void> openDeletePage(WidgetTester tester) async {
      await openSettings(tester);
      await tester.tap(find.text('Xóa tài khoản'));
      await tester.pumpAndSettle();
    }

    AppButton deleteButton(WidgetTester tester) =>
        tester.widget<AppButton>(find.widgetWithText(AppButton, 'Xóa vĩnh viễn'));

    testWidgets('warns what is lost and requires the password', (tester) async {
      await openDeletePage(tester);
      expect(find.text('Không hoàn tác được'), findsOneWidget);
      expect(find.text('Xóa tài khoản me@example.com, mọi máy và mọi ghép nối.'), findsOneWidget);
      expect(find.text('Mọi máy tính đang đăng nhập sẽ bị đăng xuất.'), findsOneWidget);
      expect(deleteButton(tester).state, ButtonState.disable);

      await tester.enterText(find.byType(TextField), 'correct horse');
      await tester.pump();
      expect(deleteButton(tester).state, ButtonState.available);
      await tester.tap(find.text('Xóa vĩnh viễn'));
      await tester.pumpAndSettle();
      expect(session.deletePasswords, ['correct horse']);
    });

    testWidgets('a wrong password shows "Mật khẩu không đúng." under the field', (tester) async {
      session.deleteError = const ApiException(status: 401, code: 'invalid_credentials', message: 'no');
      await openDeletePage(tester);
      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.pump();
      await tester.tap(find.text('Xóa vĩnh viễn'));
      await tester.pumpAndSettle();
      expect(find.text('Mật khẩu không đúng.'), findsOneWidget);
      expect(popups.errors, isEmpty);

      await tester.enterText(find.byType(TextField), 'wrong again');
      await tester.pump();
      expect(find.text('Mật khẩu không đúng.'), findsNothing);
    });

    testWidgets('"Hủy" goes back to Settings', (tester) async {
      await openDeletePage(tester);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(find.text('ShellX 1.0.0 (1)'), findsOneWidget);
    });

    testWidgets('rate limiting shows the spec message', (tester) async {
      session.deleteError = const ApiException(status: 429, code: 'rate_limited', message: 'slow');
      await openDeletePage(tester);
      await tester.enterText(find.byType(TextField), 'pw');
      await tester.pump();
      await tester.tap(find.text('Xóa vĩnh viễn'));
      await tester.pumpAndSettle();
      expect(find.text('Thử lại sau ít phút.'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd apps/mobile && flutter test test/features/settings/settings_page_test.dart`
Expected: FAIL — `SettingsController`, `DeleteAccountController`, `SettingsRoute`, `DeleteAccountRoute` are not defined.

- [ ] **Step 3: Controllers**

`apps/mobile/lib/features/settings/presentation/controllers/settings_controller.dart`:

```dart
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/lock/domain/biometric_authenticator.dart';
import 'package:shellx_mobile/features/lock/presentation/app_lock_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';

/// A computer pinned on this phone; [name] is null while `GET /v1/devices` is unreachable.
typedef PairedMachine = ({String agentId, String? name});

/// Spec §9.2 #5: default font size, biometric lock, unpair per machine, sign out, version.
@injectable
class SettingsController extends Controller {
  SettingsController(this._session, this.settings, this._lock, this._biometrics, this._registry, this._packageInfo);

  final SessionHolder _session;
  final AppSettings settings;
  final AppLockController _lock;
  final BiometricAuthenticator _biometrics;
  final WorkspaceRegistry _registry;
  final PackageInfo _packageInfo;
  final Signal<bool> _biometricsAvailable = signal(false);
  final Signal<List<PairedMachine>?> _paired = signal(null);
  bool _disposed = false;

  String get email => _session.session.peek()?.email ?? '';
  String get version => _packageInfo.version;
  String get buildNumber => _packageInfo.buildNumber;

  /// Face ID, Touch ID, fingerprint… — names the switch ("Khóa bằng Face ID").
  ReadonlySignal<BiometricKind> get lockKind => _lock.kind;

  /// False when the device has no passcode and no biometrics: the switch is disabled.
  ReadonlySignal<bool> get biometricsAvailable => _biometricsAvailable;

  /// Pinned machines with their names; null while loading.
  ReadonlySignal<List<PairedMachine>?> get paired => _paired;

  Future<void> load() async {
    final available = await _biometrics.isAvailable();
    if (_disposed) return;
    _biometricsAvailable.value = available;
    await _loadPaired();
  }

  Future<void> _loadPaired() async {
    final backend = _session.requireBackend;
    final pins = await backend.pinnedMachines();
    var names = <String, String>{};
    try {
      names = {for (final device in await backend.devices()) device.id: device.name};
    } on Object {
      // Offline: still list the pinned machines, without names.
    }
    if (_disposed) return;
    _paired.value = [for (final pin in pins) (agentId: pin.agentId, name: names[pin.agentId])];
  }

  Future<void> setFontSize(double size) => settings.setFontSize(size);

  Future<void> setBiometricLock(bool enabled) async {
    await settings.setBiometricLock(enabled);
    _lock.settingChanged();
  }

  /// Spec §5.5: drop the pin and the pairing record, and the machine's open tabs.
  Future<void> unpair(String agentId) async {
    await guard(() async {
      await _session.requireBackend.unpair(agentId);
      _registry.remove(agentId);
    });
    if (!_disposed) await _loadPaired();
  }

  /// Only the token is deleted (spec §5.2); `SessionEnforcer` returns to the login page.
  Future<void> logout() => _session.logout();

  void dispose() {
    _disposed = true;
    _biometricsAvailable.dispose();
    _paired.dispose();
  }
}
```

`apps/mobile/lib/features/settings/presentation/controllers/delete_account_controller.dart`:

```dart
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Spec §5.2 (App Store 5.1.1(v)): delete the account after re-entering the password.
@injectable
class DeleteAccountController extends Controller {
  DeleteAccountController(this._session);

  final SessionHolder _session;
  final Signal<bool> _busy = signal(false);
  final Signal<String?> _error = signal(null);
  bool _disposed = false;

  ReadonlySignal<bool> get busy => _busy;

  /// Shown under the password field: "Mật khẩu không đúng.", "Thử lại sau ít phút.", …
  ReadonlySignal<String?> get error => _error;

  String get email => _session.session.peek()?.email ?? '';

  void clearError() => _error.value = null;

  /// On success `SessionEnforcer` leaves the signed-in pages.
  Future<void> delete(String password) async {
    _busy.value = true;
    _error.value = null;
    await guard(
      () async {
        try {
          await _session.deleteAccount(password);
        } catch (error) {
          if (!_disposed) _error.value = _message(error);
          rethrow;
        }
      },
      showError: false,
    );
    if (!_disposed) _busy.value = false;
  }

  String _message(Object error) => switch (error) {
    ApiException(code: 'invalid_credentials') => S.current.errorWrongPassword,
    _ => errorFactory.fromException(error).title,
  };

  void dispose() {
    _disposed = true;
    _busy.dispose();
    _error.dispose();
  }
}
```

- [ ] **Step 4: Pages**

`apps/mobile/lib/features/settings/presentation/pages/settings_page.dart`:

```dart
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/lock/presentation/biometric_method.dart';
import 'package:shellx_mobile/features/settings/presentation/controllers/settings_controller.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Spec §9.2 #5 and the design's "Cài đặt": grouped cards — Terminal (font size with a live
/// preview), Security (biometric lock), paired computers, account — and the version footer
/// (it opens the open-source licences, incl. both fonts' OFL).
@RoutePage()
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final SettingsController _controller = getIt<SettingsController>();

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _unpair(PairedMachine machine) async {
    final strings = S.of(context);
    final confirmed = await showConfirmDialog(
      context,
      message: strings.settingsUnpairConfirm(machine.name ?? strings.unknownMachine),
      confirmLabel: strings.settingsUnpair,
    );
    if (confirmed) await _controller.unpair(machine.agentId);
  }

  Future<void> _logout() async {
    final strings = S.of(context);
    final confirmed = await showConfirmDialog(
      context,
      message: strings.settingsLogoutConfirm,
      confirmLabel: strings.settingsLogout,
    );
    if (confirmed) await _controller.logout();
  }

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final colors = context.colors;
    final settings = _controller.settings;
    final version = strings.settingsVersion(_controller.version, _controller.buildNumber);
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: Text(strings.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _Group(
            header: strings.settingsTerminalGroup,
            children: [
              Watch((context) {
                final fontSize = settings.fontSize.value;
                return Column(
                  children: [
                    _Row(
                      title: strings.settingsFontSize,
                      trailing: Text(
                        fontSize.toStringAsFixed(0),
                        style: context.typo.paragraph.copyWith(color: colors.secondaryText),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      child: Row(
                        children: [
                          Text('A', style: context.typo.metadata11.copyWith(color: colors.disable)),
                          Expanded(
                            child: Slider(
                              min: AppSettings.minFontSize,
                              max: AppSettings.maxFontSize,
                              divisions: (AppSettings.maxFontSize - AppSettings.minFontSize).round(),
                              value: fontSize,
                              label: fontSize.toStringAsFixed(0),
                              onChanged: _controller.setFontSize,
                            ),
                          ),
                          Text('A', style: context.typo.title.copyWith(color: colors.disable)),
                        ],
                      ),
                    ),
                    _FontPreview(fontSize: fontSize),
                  ],
                );
              }),
            ],
          ),
          _Group(
            header: strings.settingsSecurityGroup,
            footer: Watch(
              (context) => Text(
                _controller.biometricsAvailable.value
                    ? strings.settingsLockFootnote
                    : strings.settingsBiometricUnavailable,
                style: context.typo.metadata12.copyWith(color: colors.disable),
              ),
            ),
            children: [
              Watch((context) {
                final available = _controller.biometricsAvailable.value;
                return SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 15),
                  title: Text(
                    strings.settingsLockWith(biometricMethod(strings, _controller.lockKind.value)),
                    style: context.typo.subHeader15,
                  ),
                  value: available && settings.biometricLock.value,
                  onChanged: available ? _controller.setBiometricLock : null,
                );
              }),
            ],
          ),
          _Group(
            header: strings.settingsPairedMachines,
            children: [
              Watch((context) {
                final machines = _controller.paired.value;
                if (machines == null) {
                  return const Padding(padding: EdgeInsets.all(15), child: AppCircularProgress(size: 24));
                }
                if (machines.isEmpty) return _Row(title: strings.settingsNoPairedMachines, muted: true);
                return Column(
                  children: [
                    for (final (i, machine) in machines.indexed) ...[
                      if (i > 0) Divider(height: 1, color: colors.divider),
                      _Row(
                        title: machine.name ?? strings.unknownMachine,
                        trailing: TextButton(
                          onPressed: () => _unpair(machine),
                          child: Text(
                            strings.settingsUnpair,
                            style: context.typo.paragraph.bold.copyWith(color: colors.error),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              }),
            ],
          ),
          _Group(
            header: strings.settingsAccountGroup,
            footer: Center(
              child: GestureDetector(
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: strings.appTitle,
                  applicationVersion: '${_controller.version} (${_controller.buildNumber})',
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(version, style: context.typo.metadata12.copyWith(color: colors.disable)),
                ),
              ),
            ),
            children: [
              _Row(
                title: strings.settingsEmail,
                trailing: Text(_controller.email, style: context.typo.paragraph.copyWith(color: colors.secondaryText)),
              ),
              Divider(height: 1, color: colors.divider),
              _Row(
                title: strings.settingsLogout,
                leading: Icon(Icons.logout, color: colors.secondaryText),
                onTap: _logout,
              ),
              Divider(height: 1, color: colors.divider),
              _Row(
                title: strings.settingsDeleteAccount,
                leading: Icon(Icons.delete_outline, color: colors.error),
                danger: true,
                onTap: () => context.router.push(const DeleteAccountRoute()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// `.grp`: an upper-case header, a rounded card and an optional footnote.
class _Group extends StatelessWidget {
  const _Group({required this.header, required this.children, this.footer});

  final String header;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 7),
            child: Text(
              header.toUpperCase(),
              style: context.typo.paragraph13.bold.copyWith(color: colors.secondaryText, letterSpacing: 0.8),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.divider),
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              type: MaterialType.transparency,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
          if (footer != null) Padding(padding: const EdgeInsets.fromLTRB(6, 7, 6, 0), child: footer),
        ],
      ),
    );
  }
}

/// `.ri`: one 50 pt row of a settings card.
class _Row extends StatelessWidget {
  const _Row({required this.title, this.leading, this.trailing, this.onTap, this.danger = false, this.muted = false});

  final String title;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = danger
        ? context.typo.subHeader15.bold.copyWith(color: colors.error)
        : context.typo.subHeader15.copyWith(color: muted ? colors.secondaryText : colors.primaryText);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 50),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Row(
            children: [
              if (leading != null) ...[leading!, 10.sizedWidth],
              Expanded(child: Text(title, style: style)),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// A prompt in the terminal font at the chosen size (design `.preview`).
class _FontPreview extends StatelessWidget {
  const _FontPreview({required this.fontSize});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontFamily: FontFamily.jetBrainsMono, fontSize: fontSize, height: 1.3);
    return Container(
      margin: const EdgeInsets.fromLTRB(15, 0, 15, 14),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(color: TerminalColors.background, borderRadius: BorderRadius.circular(10)),
      child: Text.rich(
        TextSpan(
          style: style.copyWith(color: TerminalColors.foreground),
          children: const [
            TextSpan(
              text: 'user@macbook',
              style: TextStyle(color: TerminalColors.green),
            ),
            TextSpan(text: ' '),
            TextSpan(
              text: '~',
              style: TextStyle(color: TerminalColors.cyan),
            ),
            TextSpan(
              text: ' % ',
              style: TextStyle(color: TerminalColors.dim),
            ),
            TextSpan(text: 'ls'),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
      ),
    );
  }
}
```

`apps/mobile/lib/features/settings/presentation/pages/delete_account_page.dart`:

```dart
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/auth/presentation/widgets/password_text_field.dart';
import 'package:shellx_mobile/features/settings/presentation/controllers/delete_account_controller.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Spec §5.2 / §9.2 #5 and the design's "Xóa tài khoản": what is lost, password re-entry, the
/// error under the field, a red button and "Hủy".
@RoutePage()
class DeleteAccountPage extends StatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  State<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends State<DeleteAccountPage> {
  final DeleteAccountController _controller = getIt<DeleteAccountController>();
  final TextEditingController _password = TextEditingController();
  final Signal<bool> _hasPassword = signal(false);

  @override
  void dispose() {
    _password.dispose();
    _hasPassword.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final colors = context.colors;
    Widget bullet(String text) => Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: context.typo.paragraph.copyWith(color: colors.secondaryText)),
          Expanded(
            child: Text(text, style: context.typo.paragraph.copyWith(color: colors.secondaryText)),
          ),
        ],
      ),
    );
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: Text(strings.deleteAccountTitle)),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
                      decoration: BoxDecoration(color: colors.errorSoft, borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            strings.deleteAccountWarningTitle,
                            style: context.typo.subHeader15.bold.copyWith(color: colors.error),
                          ),
                          6.sizedHeight,
                          bullet(strings.deleteAccountLoseAccount(_controller.email)),
                          bullet(strings.deleteAccountLoseComputers),
                          bullet(strings.deleteAccountLoseSessions),
                        ],
                      ),
                    ),
                    18.sizedHeight,
                    Watch(
                      (context) => PasswordTextField(
                        label: strings.deleteAccountPasswordLabel,
                        hintText: strings.passwordHint,
                        controller: _password,
                        errorText: _controller.error.value,
                        autofillHints: const [AutofillHints.password],
                        onChanged: (value) {
                          _hasPassword.value = value.isNotEmpty;
                          _controller.clearError();
                        },
                      ),
                    ),
                    const Spacer(),
                    24.sizedHeight,
                    Watch((context) {
                      final state = _controller.busy.value
                          ? ButtonState.loading
                          : _hasPassword.value
                          ? ButtonState.available
                          : ButtonState.disable;
                      return AppButton(
                        title: strings.deleteAccountButton,
                        width: double.infinity,
                        backgroundColor: colors.error,
                        textColor: colors.white,
                        state: state,
                        onTap: () => _controller.delete(_password.text),
                      );
                    }),
                    4.sizedHeight,
                    AppButton(
                      title: strings.actionCancel,
                      width: double.infinity,
                      backgroundColor: Colors.transparent,
                      textColor: colors.primary,
                      onTap: () => context.router.maybePop(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Generate, run the tests, analyze**

```bash
cd apps/mobile
dart run build_runner build
flutter test test/features/settings/settings_page_test.dart
flutter analyze
flutter test
```

Expected: `+10: All tests passed!`; `No issues found!`; `+302: All tests passed!`.

- [ ] **Step 6: Commit**

```bash
git add apps/mobile
git commit -m "feat(mobile): settings and account deletion as designed"
```

---

### Task 17: `MachineListController` — devices + PRESENCE + pins

**Files:**
- Create: `apps/mobile/lib/features/machines/domain/machine_entry.dart`
- Create: `apps/mobile/lib/features/machines/presentation/controllers/machine_list_controller.dart`
- Test: `apps/mobile/test/features/machines/machine_list_controller_test.dart`

**Interfaces:**
- Consumes: `ShellxBackend.devices/pinnedMachines/isOnline/presence/relayState/relayStates` (Task 10); `SessionHolder.requireBackend/reconnectReplaced` (Task 11); `WorkspaceRegistry.tabCount` (Task 13); `RemoteDevice`, `DeviceKind`, `DevicePlatform`, `PresenceFrame`, `RelayConnectionState`; the base `StateSignal` and `Controller.mainStateGuard` (a failed refresh keeps the last data and puts the `ErrorText` text in `state.error`).
- Produces:
  - `final class MachineEntry extends Equatable { const MachineEntry({required String id, required String name, required DevicePlatform platform, required bool online, required DateTime? lastSeenAt, required bool paired}); MachineEntry copyWith({bool? online, DateTime? lastSeenAt}); }`, `final class MachineList extends Equatable { const MachineList(List<MachineEntry> machines); }`
  - `@injectable class MachineListController extends Controller { MachineListController({required ShellxBackend backend, WorkspaceRegistry? registry, Future<void> Function()? onReconnectReplaced, DateTime Function()? now}); @factoryMethod static MachineListController create(SessionHolder, WorkspaceRegistry); final StateSignal<MachineList> state; ShellxBackend get backend; ReadonlySignal<bool> get waiting; DateTime now(); int tabsOpen(String agentId); void reconnectReplaced(); Future<void> refresh(); void dispose(); }`

Rules: agents only; online machines first, then offline, each sorted by name (the design's "Offline" group); `paired` = pinned locally for this user (the server's `paired_with_me` is display-only; trust lives on the agent, spec §5.4); `online` = hub PRESENCE while the relay is connected, else the REST snapshot; PRESENCE offline stamps "last online" with the local clock; PRESENCE from an unknown agent and every reconnect trigger a refresh; `waiting` is true while the relay is not connected (the design dims every card with "Đang chờ kết nối").

- [ ] **Step 1: Write the failing test**

`apps/mobile/test/features/machines/machine_list_controller_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/machines/presentation/controllers/machine_list_controller.dart';
import 'package:shellx_mobile/shared/shared.dart';

import '../../support/fakes.dart';

void main() {
  final now = DateTime(2026, 9, 25, 12);
  late FakeBackend backend;
  late MachineListController controller;

  setUp(() async {
    await S.load(const Locale('vi'));
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

  List<String> names() => [for (final machine in controller.state.value.machines) machine.name];

  test('lists agents only, sorted by name, with the local pin as "paired"', () async {
    backend.onlineIds.add(agentA);
    await controller.refresh();
    expect(names(), ['MacBook-Pro', 'zeta-pc']);
    final machines = controller.state.value.machines;
    expect(machines.first.paired, isTrue);
    expect(machines.last.paired, isFalse);
    expect(machines.last.lastSeenAt, now.subtract(const Duration(hours: 2)));
  });

  test('uses PRESENCE while connected and the REST snapshot otherwise', () async {
    await controller.refresh();
    expect(controller.state.value.machines.first.online, isFalse); // hub says nothing is online

    backend.relayStateValue = RelayConnectionState.disconnected;
    await controller.refresh();
    expect(controller.state.value.machines.first.online, isTrue); // REST says online
  });

  test('PRESENCE offline greys the machine and stamps "last online" now', () async {
    backend.onlineIds.add(agentA);
    await controller.refresh();
    var updates = -1; // the effect runs once right away
    final stop = effect(() {
      controller.state.value;
      updates++;
    });
    addTearDown(stop);

    backend.emitPresence(agentA, online: false);

    final mac = controller.state.value.machines.firstWhere((m) => m.id == agentA);
    expect(mac.online, isFalse);
    expect(mac.lastSeenAt, now);
    expect(updates, 1);

    backend.emitPresence(agentA, online: true);
    expect(controller.state.value.machines.firstWhere((m) => m.id == agentA).online, isTrue);
  });

  test('PRESENCE from an unknown computer refreshes the list', () async {
    await controller.refresh();
    backend.deviceList = [...backend.deviceList, agentDevice('55555555-5555-4555-8555-555555555555', 'new-box')];
    backend.emitPresence('55555555-5555-4555-8555-555555555555', online: true);
    await pumpEventQueue();
    expect(names(), contains('new-box'));
  });

  test('refreshes when the relay reconnects', () async {
    await controller.refresh();
    backend.deviceList = [agentDevice(agentA, 'renamed')];
    backend.emitRelay(RelayConnectionState.connected);
    await pumpEventQueue();
    expect(names(), ['renamed']);
  });

  test('keeps the last list and holds the spec text when the refresh fails', () async {
    await controller.refresh();
    backend.devicesError = const ApiException(status: 429, code: 'rate_limited', message: 'slow');
    await controller.refresh();
    expect(controller.state.value.machines, hasLength(2));
    expect(controller.state.hasError, isTrue);
    expect(controller.state.error?.title, 'Thử lại sau ít phút.');
    expect(controller.state.error?.originalError, isA<ApiException>());
    expect(controller.state.isLoading, isFalse);
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd apps/mobile && flutter test test/features/machines/machine_list_controller_test.dart`
Expected: FAIL — `Error when reading 'lib/features/machines/presentation/controllers/machine_list_controller.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/mobile/lib/features/machines/domain/machine_entry.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:shellx_core/shellx_core.dart';

/// One computer (agent) of the account as shown on the machine list.
final class MachineEntry extends Equatable {
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

  @override
  List<Object?> get props => [id, name, platform, online, lastSeenAt, paired];
}

/// The machine list as one value for a `StateSignal`.
final class MachineList extends Equatable {
  const MachineList(this.machines);

  final List<MachineEntry> machines;

  @override
  List<Object?> get props => [machines];
}
```

`apps/mobile/lib/features/machines/presentation/controllers/machine_list_controller.dart`:

```dart
import 'dart:async';

import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/machines/domain/machine_entry.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';

/// Spec §9.2 #2: agents from `GET /v1/devices`, kept live with PRESENCE.
@injectable
class MachineListController extends Controller {
  MachineListController({
    required ShellxBackend backend,
    WorkspaceRegistry? registry,
    Future<void> Function()? onReconnectReplaced,
    DateTime Function()? now,
  }) : _backend = backend,
       _registry = registry,
       _onReconnectReplaced = onReconnectReplaced,
       _now = now ?? DateTime.now {
    _relayState = signal(backend.relayState);
    _presence = backend.presence.listen(_onPresence);
    _relay = backend.relayStates.listen((state) {
      _relayState.value = state;
      // Presence may have been missed while disconnected.
      if (state == RelayConnectionState.connected) unawaited(refresh());
    });
  }

  @factoryMethod
  static MachineListController create(SessionHolder session, WorkspaceRegistry registry) => MachineListController(
    backend: session.requireBackend,
    registry: registry,
    onReconnectReplaced: session.reconnectReplaced,
  );

  final ShellxBackend _backend;
  final WorkspaceRegistry? _registry;
  final Future<void> Function()? _onReconnectReplaced;
  final DateTime Function() _now;
  late final Signal<RelayConnectionState> _relayState;
  late final Computed<bool> _waiting = computed(() => _relayState.value != RelayConnectionState.connected);
  late final StreamSubscription<PresenceFrame> _presence;
  late final StreamSubscription<RelayConnectionState> _relay;

  /// Online machines first, then offline, each sorted by name; agents only. A failed refresh
  /// keeps the last list and holds the spec §12 text in `state.error`.
  final StateSignal<MachineList> state = StateSignal(const MachineList([]));

  ShellxBackend get backend => _backend;

  /// The relay is not connected: cards dim, say "Đang chờ kết nối" and cannot be opened.
  ReadonlySignal<bool> get waiting => _waiting;

  /// The clock "Lần cuối online: …" is measured against.
  DateTime now() => _now();

  /// Tabs open on this phone for [agentId] ("2 tab").
  int tabsOpen(String agentId) => _registry?.tabCount(agentId) ?? 0;

  /// "Kết nối lại" after close code 4001 (spec §12).
  void reconnectReplaced() => unawaited(_onReconnectReplaced?.call());

  Future<void> refresh() => mainStateGuard(_load, state: state);

  Future<MachineList> _load() async {
    final devices = await _backend.devices();
    final pinned = {for (final machine in await _backend.pinnedMachines()) machine.agentId};
    final live = _backend.relayState == RelayConnectionState.connected;
    return _sorted([
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
    ]);
  }

  /// Design "Danh sách máy": online on top, "Offline" below.
  MachineList _sorted(List<MachineEntry> machines) {
    int byName(MachineEntry a, MachineEntry b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return MachineList(
      List.unmodifiable([
        ...machines.where((m) => m.online).toList()..sort(byName),
        ...machines.where((m) => !m.online).toList()..sort(byName),
      ]),
    );
  }

  void _onPresence(PresenceFrame frame) {
    final machines = state.peek().machines;
    final index = machines.indexWhere((machine) => machine.id == frame.deviceId);
    if (index < 0) {
      // A computer that just registered: fetch its name.
      if (frame.online) unawaited(refresh());
      return;
    }
    final machine = machines[index];
    if (machine.online == frame.online) return;
    final updated = List.of(machines)
      ..[index] = machine.copyWith(online: frame.online, lastSeenAt: frame.online ? null : _now());
    state.value = _sorted(updated);
  }

  void dispose() {
    unawaited(_presence.cancel());
    unawaited(_relay.cancel());
    _waiting.dispose();
    _relayState.dispose();
    state.dispose();
  }
}
```

- [ ] **Step 4: Generate, run the test, analyze**

```bash
cd apps/mobile
dart run build_runner build
flutter test test/features/machines/machine_list_controller_test.dart
flutter analyze
flutter test
```

Expected: `+6: All tests passed!`; `No issues found!`; `+308: All tests passed!`.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile
git commit -m "feat(mobile): machine list controller with devices, presence and pins"
```

---

### Task 18: Machine list page and the "Cần cập nhật app" page

UI per the design's "Danh sách máy" screens (binding): a gear button, the title "Máy của bạn", the connection banner while the relay reconnects (every card then dimmed with "Đang chờ kết nối" and not tappable) or after 4001 ("Kết nối lại"); online machines first as cards (OS icon, name, green dot + "Online", "N tab" pill when tabs are open on this phone, "Chưa ghép nối" badge when not paired), then an "OFFLINE" group header and the offline cards — dimmed, "Lần cuối online: …", not tappable; "Ghép nối máy mới" at the bottom. First run (no machines): three numbered steps (install from shellx.pro, sign in with this account, ShellX icon → "Ghép nối điện thoại…") and the button "Quét mã QR". Tapping an online paired machine opens its terminal; an unpaired one opens the scanner. When the terminal page closes with `TerminalExit.untrusted`, an alert "Cần ghép nối lại" with the §12 text offers "Để sau" / "Quét mã"; with `TerminalExit.updateRequired`, the "Cần cập nhật app" page opens. "Cần cập nhật app" (also the target of Task 19's update guard): a warn status circle, the title, the body and "Mở App Store" / "Mở Google Play" by platform.

**Files:**
- Create: `apps/mobile/lib/features/machines/presentation/pages/machine_list_page.dart`
- Create: `apps/mobile/lib/features/app/update_required_page.dart`
- Create: `apps/mobile/test/support/fake_links.dart`
- Test: `apps/mobile/test/features/machines/machine_list_page_test.dart`

**Interfaces:**
- Consumes: `MachineListController`, `MachineEntry` (Task 17); `formatLastSeen` (Task 9); `ConnectionBanner`, `TerminalRoute`, `TerminalExit` (Task 14); `QrScannerRoute` (Task 15); `SettingsRoute` (Task 16); `ExternalLinks`, `AppConfig` (Task 3); `StatusCircle`, `AppButton`, `HighlightedText` (Task 2).
- Produces: `@RoutePage() class MachineListPage` → `MachineListRoute()`; `class MachineCard extends StatelessWidget { const MachineCard({Key? key, required MachineEntry machine, required bool waiting, required int tabs, required DateTime now, VoidCallback? onTap}); }` (cards keyed `ValueKey('machine-<id>')`); `@RoutePage() class UpdateRequiredPage` → `UpdateRequiredRoute()`; test helper `FakeExternalLinks` (records `opened` URLs and `settingsOpened`).

The list refreshes every time a pushed page (terminal, scanner, settings) comes back.

- [ ] **Step 1: Write the failing widget tests**

`apps/mobile/test/support/fake_links.dart`:

```dart
import 'package:shellx_mobile/core/core.dart' hide test;

/// Records what the app tried to open outside itself.
class FakeExternalLinks implements ExternalLinks {
  final List<Uri> opened = [];
  int settingsOpened = 0;

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return true;
  }

  @override
  Future<void> openAppSettings() async => settingsOpened++;
}
```

`apps/mobile/test/features/machines/machine_list_page_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/machines/presentation/controllers/machine_list_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_page_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';

import '../../support/app_harness.dart';
import '../../support/fake_links.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fakes.dart';

void main() {
  const ketoan = '33333333-3333-4333-8333-333333333333';
  const vanphong = '44444444-4444-4444-8444-444444444444';
  final now = DateTime(2026, 9, 25, 12);
  late FakeBackend backend;
  late WorkspaceRegistry registry;
  late FakeExternalLinks links;
  late List<Object?> terminals;
  late List<Object?> scans;
  late List<Object?> settingsVisits;
  late List<Object?> updates;
  TerminalExit? terminalExit;

  setUp(() {
    backend = FakeBackend(
      devices: [
        agentDevice(
          vanphong,
          'PC-VANPHONG',
          online: false,
          platform: DevicePlatform.windows,
          lastSeenAt: DateTime(2026, 9, 24, 18, 5),
        ),
        agentDevice(ketoan, 'PC-KETOAN', platform: DevicePlatform.windows),
        agentDevice(agentB, 'MINI-HOME'),
        agentDevice(agentA, 'MacBook Pro của Phú'),
      ],
      pinnedList: [pinned(agentA), pinned(agentB), pinned(vanphong)],
    )..onlineIds.addAll([agentA, agentB, ketoan]);
    backend.addMachine(agentA);
    registry = WorkspaceRegistry(signal<ShellxBackend?>(backend));
    links = FakeExternalLinks();
    terminals = [];
    scans = [];
    settingsVisits = [];
    updates = [];
    terminalExit = null;
    getIt
      ..registerSingleton<PopupHandler>(FakePopupHandler())
      ..registerSingleton<ExternalLinks>(links)
      ..registerFactory<MachineListController>(
        () => MachineListController(backend: backend, registry: registry, now: () => now),
      );
  });

  tearDown(() async {
    registry.dispose();
    await getIt.reset();
  });

  /// The terminal stand-in closes with [terminalExit] when its "leave" button is tapped.
  AutoRoute terminalStub() => AutoRoute(
    page: PageInfo(
      TerminalRoute.name,
      builder: (data) {
        terminals.add(data.args);
        return Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('terminal stub')),
            body: TextButton(onPressed: () => context.router.maybePop(terminalExit), child: const Text('leave')),
          ),
        );
      },
    ),
  );

  Future<void> openList(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      routedApp(
        open: () => const MachineListRoute(),
        routes: [
          AutoRoute(page: MachineListRoute.page),
          terminalStub(),
          stubRoute(QrScannerRoute.name, pushed: scans),
          stubRoute(SettingsRoute.name, pushed: settingsVisits),
          stubRoute(UpdateRequiredRoute.name, pushed: updates),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await openPushed(tester);
  }

  Future<void> back(WidgetTester tester) async {
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  }

  Finder card(String id) => find.byKey(ValueKey('machine-$id'));

  testWidgets('design: online first, then an "Offline" group; dots, badges and last online', (tester) async {
    await openList(tester);
    expect(find.text('Máy của bạn'), findsOneWidget);
    final y = {
      for (final id in [agentA, agentB, ketoan, vanphong]) id: tester.getTopLeft(card(id)).dy,
    };
    expect(y[agentA]! < y[agentB]! && y[agentB]! < y[ketoan]!, isTrue);
    expect(tester.getTopLeft(find.text('OFFLINE')).dy, inExclusiveRange(y[ketoan]!, y[vanphong]!));

    expect(find.descendant(of: card(agentA), matching: find.byKey(const ValueKey('dot-online'))), findsOneWidget);
    expect(find.descendant(of: card(agentA), matching: find.text('Online · macOS')), findsOneWidget);
    expect(find.descendant(of: card(ketoan), matching: find.text('Chưa ghép nối')), findsOneWidget);
    expect(find.descendant(of: card(vanphong), matching: find.byKey(const ValueKey('dot-offline'))), findsOneWidget);
    expect(find.text('Lần cuối online: hôm qua, 18:05'), findsOneWidget);
    expect(find.text('Ghép nối máy mới'), findsOneWidget);
  });

  testWidgets('online paired opens the terminal; unpaired opens the scanner; offline is not tappable', (tester) async {
    await openList(tester);
    await tester.tap(card(agentA));
    await tester.pumpAndSettle();
    final args = terminals.single as TerminalRouteArgs;
    expect((args.agentId, args.machineName), (agentA, 'MacBook Pro của Phú'));
    await back(tester);

    await tester.tap(card(vanphong));
    await tester.pumpAndSettle();
    expect(terminals, hasLength(1));
    expect(scans, isEmpty);
    expect(find.text('Máy của bạn'), findsOneWidget);

    await tester.tap(card(ketoan));
    await tester.pumpAndSettle();
    expect(scans, hasLength(1));
  });

  testWidgets('"N tab" counts the tabs open on this phone', (tester) async {
    final workspace = registry.forMachine(agentA);
    await workspace.openNew((cols: 80, rows: 24));
    await workspace.openNew((cols: 80, rows: 24));
    await openList(tester);
    expect(find.descendant(of: card(agentA), matching: find.text('2 tab')), findsOneWidget);
    expect(find.descendant(of: card(agentB), matching: find.textContaining('tab')), findsNothing);
  });

  testWidgets('while the relay reconnects: banner, dimmed "Đang chờ kết nối" cards, no taps', (tester) async {
    await openList(tester);
    backend.emitRelay(RelayConnectionState.disconnected);
    await tester.pump();
    expect(find.text('Mất kết nối, đang thử lại…'), findsOneWidget);
    expect(find.text('Đang chờ kết nối'), findsNWidgets(4));
    await tester.tap(card(agentA));
    await tester.pump();
    expect(terminals, isEmpty);

    backend.emitRelay(RelayConnectionState.connected);
    await tester.pumpAndSettle();
    expect(find.text('Mất kết nối, đang thử lại…'), findsNothing);
    expect(find.text('Online · macOS'), findsNWidgets(2));
  });

  testWidgets('an untrusted machine: "Cần ghép nối lại" offers "Quét mã"', (tester) async {
    terminalExit = TerminalExit.untrusted;
    await openList(tester);
    await tester.tap(card(agentA));
    await tester.pumpAndSettle();
    await tester.tap(find.text('leave'));
    await tester.pumpAndSettle();
    expect(find.text('Cần ghép nối lại'), findsOneWidget);
    expect(find.text('Máy không còn tin cậy điện thoại này. Hãy ghép nối lại.'), findsOneWidget);
    await tester.tap(find.text('Quét mã'));
    await tester.pumpAndSettle();
    expect(scans, hasLength(1));
  });

  testWidgets('proto_unsupported opens "Cần cập nhật app"', (tester) async {
    terminalExit = TerminalExit.updateRequired;
    await openList(tester);
    await tester.tap(card(agentA));
    await tester.pumpAndSettle();
    await tester.tap(find.text('leave'));
    await tester.pumpAndSettle();
    expect(updates, hasLength(1));
  });

  testWidgets('first run: three steps, a link to shellx.pro and "Quét mã QR"', (tester) async {
    backend.deviceList = [];
    await openList(tester);
    expect(find.text('Chưa có máy nào'), findsOneWidget);
    expect(find.text('Đăng nhập cùng tài khoản này.'), findsOneWidget);
    expect(find.textContaining('Ghép nối điện thoại…'), findsOneWidget);
    await tester.tap(find.text('shellx.pro'));
    expect(links.opened, [Uri.parse('https://shellx.pro/')]);
    await tester.tap(find.text('Quét mã QR'));
    await tester.pumpAndSettle();
    expect(scans, hasLength(1));
  });

  testWidgets('settings; the list refreshes afterwards; refresh errors show the spec text', (tester) async {
    await openList(tester);
    backend.deviceList = [agentDevice(agentA, 'Renamed-Mac')];
    await tester.tap(find.byTooltip('Cài đặt'));
    await tester.pumpAndSettle();
    expect(settingsVisits, hasLength(1));
    await back(tester);
    expect(find.text('Renamed-Mac'), findsOneWidget);

    backend.devicesError = const ApiException(status: 429, code: 'rate_limited', message: 'slow');
    await tester.fling(find.byType(CustomScrollView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Thử lại sau ít phút.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd apps/mobile && flutter test test/features/machines/machine_list_page_test.dart`
Expected: FAIL — `MachineListRoute` and `UpdateRequiredRoute` are not defined.

- [ ] **Step 3: Implement**

`apps/mobile/lib/features/app/update_required_page.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Spec §12/§14 and the design's "Lệch phiên bản": `/v1/version` is newer than the app, or a
/// machine answered `proto_unsupported`. The button opens the store of this platform.
@RoutePage()
class UpdateRequiredPage extends StatelessWidget {
  const UpdateRequiredPage({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            children: [
              const Spacer(),
              const StatusCircle(icon: Icons.system_update_alt, tone: StatusTone.warn),
              16.sizedHeight,
              Text(strings.updateRequiredTitle, style: context.typo.heading26.heavy),
              12.sizedHeight,
              Text(
                strings.updateRequiredBody,
                textAlign: TextAlign.center,
                style: context.typo.subHeader15.copyWith(color: context.colors.secondaryText),
              ),
              const Spacer(),
              AppButton(
                title: ios ? strings.openAppStore : strings.openPlayStore,
                width: double.infinity,
                onTap: () => getIt<ExternalLinks>().open(ios ? AppConfig.appStorePage : AppConfig.playStorePage),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

`apps/mobile/lib/features/machines/presentation/pages/machine_list_page.dart`:

```dart
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/app/connection_banner.dart';
import 'package:shellx_mobile/features/machines/domain/machine_entry.dart';
import 'package:shellx_mobile/features/machines/presentation/controllers/machine_list_controller.dart';
import 'package:shellx_mobile/features/machines/presentation/last_seen.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_page_controller.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Spec §9.2 #2 / §12 and the design's "Máy của bạn": online machines first, an "Offline" group
/// (dimmed, not tappable), "Chưa ghép nối" opens the scanner, "N tab" counts the tabs open on this
/// phone; the first run shows three pairing steps.
@RoutePage()
class MachineListPage extends StatefulWidget {
  const MachineListPage({super.key});

  @override
  State<MachineListPage> createState() => _MachineListPageState();
}

class _MachineListPageState extends State<MachineListPage> {
  final MachineListController _controller = getIt<MachineListController>();

  @override
  void initState() {
    super.initState();
    _controller.refresh();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Pairing, unpairing and new tabs happen on the pushed pages: refresh when they close.
  Future<void> _then(Future<Object?> navigation) async {
    await navigation;
    if (mounted) await _controller.refresh();
  }

  Future<void> _scan() => _then(context.router.push(QrScannerRoute()));

  Future<void> _open(MachineEntry machine) async {
    final exit = await context.router.push<TerminalExit>(TerminalRoute(agentId: machine.id, machineName: machine.name));
    if (!mounted) return;
    await _controller.refresh();
    if (!mounted) return;
    switch (exit) {
      case TerminalExit.untrusted:
        await _askToPairAgain();
      case TerminalExit.updateRequired:
        await context.router.push(const UpdateRequiredRoute());
      case null:
        break;
    }
  }

  /// Design "Máy đã thu hồi điện thoại": the pin is already gone; offer to scan again.
  Future<void> _askToPairAgain() async {
    final strings = S.of(context);
    final scan = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.untrustedTitle, textAlign: TextAlign.center, style: context.typo.title.bold),
        content: Text(
          strings.errorUntrusted,
          textAlign: TextAlign.center,
          style: context.typo.paragraph.copyWith(color: context.colors.secondaryText),
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(strings.actionLater)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.actionScanCode, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (scan == true && mounted) await _scan();
  }

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 52,
              child: Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: strings.settingsTooltip,
                  icon: Icon(Icons.settings_outlined, color: context.colors.primary),
                  onPressed: () => _then(context.router.push(const SettingsRoute())),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(strings.machinesTitle, style: context.typo.display32.heavy),
            ),
            ConnectionBanner(
              backend: _controller.backend,
              onReconnectReplaced: _controller.reconnectReplaced,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            ),
            Expanded(
              child: Watch((context) {
                final state = _controller.state;
                final machines = state.value.machines;
                if (!state.isLoading && !state.hasError && machines.isEmpty) {
                  return _EmptyState(onScan: _scan);
                }
                final waiting = _controller.waiting.value;
                final online = machines.where((m) => m.online).toList();
                final offline = machines.where((m) => !m.online).toList();
                MachineCard card(MachineEntry machine) => MachineCard(
                  machine: machine,
                  waiting: waiting,
                  tabs: _controller.tabsOpen(machine.id),
                  now: _controller.now(),
                  onTap: waiting || !machine.online
                      ? null
                      : machine.paired
                      ? () => _open(machine)
                      : _scan,
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: AppScrollView(
                        onRefresh: _controller.refresh,
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            sliver: SliverOpacity(
                              opacity: waiting ? 0.55 : 1,
                              sliver: SliverList.list(
                                children: [
                                  if (state.isLoading && machines.isEmpty) const LinearProgressIndicator(),
                                  if (state.hasError && state.error != null)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: NoticeBanner(
                                        text: state.error!.title,
                                        leading: const Icon(Icons.error_outline),
                                      ),
                                    ),
                                  for (final machine in online) card(machine),
                                  if (offline.isNotEmpty) _GroupHeader(strings.machinesOfflineHeader),
                                  for (final machine in offline) card(machine),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      child: AppButton(
                        title: strings.pairNewMachine,
                        backgroundColor: context.colors.primarySoft,
                        textColor: context.colors.primary,
                        prefix: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(Icons.qr_code_2, color: context.colors.primary),
                        ),
                        onTap: _scan,
                      ),
                    ),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
    child: Text(
      text.toUpperCase(),
      style: context.typo.paragraph13.bold.copyWith(color: context.colors.secondaryText, letterSpacing: 0.8),
    ),
  );
}

/// One computer (`.m`): OS tile, name, status line, "N tab" and the right-hand hint.
class MachineCard extends StatelessWidget {
  const MachineCard({
    super.key,
    required this.machine,
    required this.waiting,
    required this.tabs,
    required this.now,
    required this.onTap,
  });

  final MachineEntry machine;
  final bool waiting;
  final int tabs;
  final DateTime now;

  /// Null when the card cannot be opened (offline, or the relay is reconnecting).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final colors = context.colors;
    final online = machine.online && !waiting;
    final platform = machine.platform == DevicePlatform.windows ? 'Windows' : 'macOS';
    final detail = waiting
        ? strings.machineWaiting
        : machine.online
        ? '${strings.machineOnline} · $platform'
        : strings.machineLastOnline(formatLastSeen(strings, machine.lastSeenAt, now));
    return Padding(
      key: ValueKey('machine-${machine.id}'),
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colors.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(13, 13, 14, 13),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: machine.online ? colors.primarySoft : colors.divider,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    machine.platform == DevicePlatform.windows ? Icons.desktop_windows_outlined : Icons.laptop_mac,
                    color: machine.online ? colors.primary : colors.disable,
                  ),
                ),
                13.sizedWidth,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        machine.name,
                        style: context.typo.subHeader.bold.copyWith(
                          color: machine.online ? colors.primaryText : colors.secondaryText,
                        ),
                      ),
                      3.sizedHeight,
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          Container(
                            key: ValueKey(online ? 'dot-online' : 'dot-offline'),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: online ? colors.okDot : colors.disable,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Text(detail, style: context.typo.paragraph13.copyWith(color: colors.secondaryText)),
                          if (tabs > 0 && !waiting)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: colors.divider,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                strings.machineTabs(tabs),
                                style: context.typo.metadata12.bold.copyWith(color: colors.secondaryText),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!machine.paired)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(color: colors.primarySoft, borderRadius: BorderRadius.circular(999)),
                    child: Text(
                      strings.machineNotPaired,
                      style: context.typo.metadata12.bold.copyWith(color: colors.primary),
                    ),
                  )
                else if (onTap != null)
                  Icon(Icons.chevron_right, color: colors.disable),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Design "Lần đầu dùng": the three pairing steps and "Quét mã QR".
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onScan});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final colors = context.colors;
    final text = context.typo.subHeader15;
    const site = 'shellx.pro';
    final menu = strings.pairPhoneMenuItem;
    Widget step(int number, Widget body) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: colors.primarySoft, shape: BoxShape.circle),
          child: Text('$number', style: context.typo.paragraph.bold.copyWith(color: colors.primary)),
        ),
        12.sizedWidth,
        Expanded(child: body),
      ],
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        children: [
          SizedBox(
            width: 170,
            height: 110,
            child: Stack(
              children: [
                Positioned(left: 0, top: 0, child: Icon(Icons.laptop_mac, size: 118, color: colors.secondaryText)),
                Positioned(right: 4, bottom: 0, child: Icon(Icons.smartphone, size: 64, color: colors.primary)),
              ],
            ),
          ),
          16.sizedHeight,
          Text(strings.emptyTitle, style: context.typo.heading20.heavy),
          16.sizedHeight,
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.divider),
            ),
            child: Column(
              children: [
                step(
                  1,
                  HighlightedText(
                    strings.emptyStep1(site),
                    parts: {site: () => getIt<ExternalLinks>().open(AppConfig.downloadPage)},
                    style: text,
                    partStyle: text.bold.copyWith(color: colors.primary),
                  ),
                ),
                14.sizedHeight,
                step(2, Text(strings.emptyStep2, style: text)),
                14.sizedHeight,
                step(
                  3,
                  HighlightedText(strings.emptyStep3(menu), parts: {menu: null}, style: text, partStyle: text.bold),
                ),
              ],
            ),
          ),
          16.sizedHeight,
          AppButton(
            title: strings.scanQrButton,
            width: double.infinity,
            prefix: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.qr_code_2, color: colors.onPrimary),
            ),
            onTap: onScan,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Generate, run the tests, analyze**

```bash
cd apps/mobile
dart run build_runner build
flutter test test/features/machines/machine_list_page_test.dart
flutter analyze
flutter test
```

Expected: `+8: All tests passed!`; `No issues found!`; `+316: All tests passed!`.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile
git commit -m "feat(mobile): machine list and update-required pages as designed"
```

---

### Task 19: App shell — login/register, guards, routes, session enforcer, launch, `main()`; full verification

UI per the design's "Đăng nhập" / "Đăng ký" screens (binding). Login: the logo, "Đăng nhập", "Dùng cùng tài khoản với ShellX trên máy tính.", a banner "Phiên đăng nhập đã hết hiệu lực. Hãy đăng nhập lại." after a 4002 (or "Tài khoản đã được xóa." after deleting the account) with the last email prefilled, email and password fields, the hint "Quên mật khẩu? Đổi mật khẩu trong ShellX trên máy tính đang đăng nhập.", the button, and "Chưa có tài khoản?" + "Tạo tài khoản". Register: "Tạo tài khoản", "Một tài khoản cho điện thoại và mọi máy tính của bạn.", fields checked while typing (email format; password "Từ 8 đến 128 ký tự." / "Còn thiếu N ký tự." / "Thừa N ký tự."), the relay's `disposable_email`/`email_taken`/`weak_password` shown under the field they concern, the button dimmed until both fields are valid, and the terms line "Khi tạo tài khoản, bạn đồng ý với Điều khoản và Chính sách quyền riêng tư." with both links.

**Files:**
- Create: `apps/mobile/lib/features/auth/domain/auth_form_validator.dart`
- Create: `apps/mobile/lib/features/auth/presentation/controllers/auth_controller.dart`, `login_controller.dart`, `register_controller.dart`
- Create: `apps/mobile/lib/features/auth/presentation/pages/login_page.dart`, `register_page.dart`
- Create: `apps/mobile/lib/core/router/auth_guard.dart`, `apps/mobile/lib/core/router/update_guard.dart`, `apps/mobile/lib/core/auth/session_enforcer.dart`
- Modify: `apps/mobile/lib/core/router/app_router.dart`, `apps/mobile/lib/core/core.dart`
- Modify: `apps/mobile/lib/features/app/launch.dart`, `apps/mobile/lib/features/app/app.dart`, `apps/mobile/lib/main.dart`
- Create: `apps/mobile/lib/features/app/font_licenses.dart`
- Delete: `apps/mobile/lib/features/app/start_page.dart`
- Test: `apps/mobile/test/features/auth/auth_form_validator_test.dart`, `apps/mobile/test/features/auth/login_page_test.dart`, `apps/mobile/test/app_test.dart`

**Interfaces:**
- Consumes: everything above — `SessionHolder` (`login`, `register`, `lastEmail`, `signOutReason`, `isAuthenticated`, `restore`, `onBackground`, `onForeground`), `AuthEventNotifier`, `SignedInEvent`/`SignedOutEvent`, `VersionGate` (Task 11); `AppLockController`, `LockGate` (Task 4); `ExternalLinks`, `AppConfig` (Task 3); every page route (Tasks 14–18); the base `validateEmailWithMessages` (`lib/utils`); `Assets.licenses.*` (Task 1).
- Produces:
  - `class AuthFormValidator { static const int minPasswordLength = 8, maxPasswordLength = 128; String? validateEmail(String?); String? validatePassword(String?); String? validateNewPassword(String?); }`
  - `abstract class AuthController extends Controller { AuthController(SessionHolder); ReadonlySignal<bool> get busy; String? get lastEmail; SignOutReason? get signOutReason; Future<void> submit(String email, String password); Future<void> run(Future<void> Function() action); }`, `@injectable LoginController`, `@injectable RegisterController` (`emailError`, `passwordError`, `password`, `canSubmit` signals, `setEmail`, `setPassword`, `passwordHelp(S)`)
  - `@RoutePage() LoginPage` → `LoginRoute()`, `@RoutePage() RegisterPage` → `RegisterRoute()`
  - `@injectable AuthGuard(SessionHolder)` (signed-out → `LoginRoute`), `@injectable UpdateGuard(VersionGate)` (outdated → `UpdateRequiredRoute`), `AppRouter({required AuthGuard authGuard, required UpdateGuard updateGuard})` with every route; `SessionEnforcer` (`@Singleton(as:)`, created at startup): `SignedInEvent` → `replaceAll([MachineListRoute()])`, `SignedOutEvent` → `replaceAll([LoginRoute()])`
  - `prepareLaunch()` (final): version gate → restore the saved session unless blocked → detect the biometric kind → lock on launch; `registerFontLicenses()`.

The machine list is the initial route behind `[updateGuard, authGuard]`: a saved session opens it directly, no session lands on the login page, an outdated app on "Cần cập nhật app". The lock stays an overlay (`LockGate` in `MaterialApp.router`'s `builder`), now also driving `SessionHolder.onBackground`/`onForeground`.

- [ ] **Step 1: Write the failing tests**

`apps/mobile/test/features/auth/auth_form_validator_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/auth/domain/auth_form_validator.dart';
import 'package:shellx_mobile/shared/shared.dart';

void main() {
  final validator = AuthFormValidator();

  setUpAll(() => S.load(const Locale('vi')));

  test('email: format only, with the spec text', () {
    expect(validator.validateEmail('  me@example.com '), isNull);
    expect(validator.validateEmail('not-an-email'), 'Email không hợp lệ.');
    expect(validator.validateEmail(''), 'Email không hợp lệ.');
  });

  test('new password: 8–128 characters and no other rule (spec §5.2)', () {
    expect(validator.validateNewPassword('a' * 7), 'Mật khẩu phải có 8–128 ký tự.');
    expect(validator.validateNewPassword('a' * 8), isNull);
    expect(validator.validateNewPassword('long enough'), isNull); // no case or digit rules
    expect(validator.validateNewPassword('a' * 128), isNull);
    expect(validator.validateNewPassword('a' * 129), 'Mật khẩu phải có 8–128 ký tự.');
    expect(validator.validateNewPassword(null), 'Mật khẩu phải có 8–128 ký tự.');
  });

  test('sign-in password: only required', () {
    expect(validator.validatePassword('x'), isNull);
    expect(validator.validatePassword(''), 'Cần nhập mật khẩu');
  });
}
```

`apps/mobile/test/features/auth/login_page_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/auth/presentation/controllers/login_controller.dart';
import 'package:shellx_mobile/features/auth/presentation/controllers/register_controller.dart';
import 'package:shellx_mobile/shared/shared.dart';

import '../../support/app_harness.dart';
import '../../support/fake_links.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fakes.dart';

void main() {
  late FakeSessionHolder session;
  late FakePopupHandler popups;
  late FakeExternalLinks links;

  setUp(() {
    session = FakeSessionHolder();
    popups = FakePopupHandler();
    links = FakeExternalLinks();
    getIt
      ..registerSingleton<PopupHandler>(popups)
      ..registerSingleton<ExternalLinks>(links)
      ..registerFactory<LoginController>(() => LoginController(session))
      ..registerFactory<RegisterController>(() => RegisterController(session));
  });

  tearDown(getIt.reset);

  Future<void> openLogin(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      routedApp(
        open: () => const LoginRoute(),
        routes: [
          AutoRoute(page: LoginRoute.page),
          AutoRoute(page: RegisterRoute.page),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await openPushed(tester);
  }

  Future<void> fill(WidgetTester tester, String email, String password) async {
    await tester.enterText(find.byType(TextField).at(0), email);
    await tester.enterText(find.byType(TextField).at(1), password);
    await tester.pump();
  }

  Finder button(String title) => find.widgetWithText(AppButton, title);
  ButtonState stateOf(WidgetTester tester, String title) => tester.widget<AppButton>(button(title)).state;

  group('sign in', () {
    testWidgets('design: subtitle, forgot-password hint, "Tạo tài khoản"; signs in', (tester) async {
      await openLogin(tester);
      expect(find.text('Dùng cùng tài khoản với ShellX trên máy tính.'), findsOneWidget);
      expect(find.text('Quên mật khẩu? Đổi mật khẩu trong ShellX trên máy tính đang đăng nhập.'), findsOneWidget);
      expect(find.text('Chưa có tài khoản?'), findsOneWidget);
      await fill(tester, 'me@example.com', 'secret');
      await tester.tap(button('Đăng nhập'));
      await tester.pumpAndSettle();
      expect(session.authCalls, [('login', 'me@example.com', 'secret')]);
    });

    testWidgets('shows invalid_credentials and 429 with the spec texts', (tester) async {
      await openLogin(tester);
      await fill(tester, 'me@example.com', 'wrong');
      session.authError = const ApiException(status: 401, code: 'invalid_credentials', message: 'x');
      await tester.tap(button('Đăng nhập'));
      await tester.pumpAndSettle();

      session.authError = const ApiException(status: 429, code: 'rate_limited', message: 'x');
      await tester.tap(button('Đăng nhập'));
      await tester.pumpAndSettle();
      expect(popups.errors, ['Email hoặc mật khẩu không đúng.', 'Thử lại sau ít phút.']);
    });

    testWidgets('rejects an obviously invalid email without calling the relay', (tester) async {
      await openLogin(tester);
      await fill(tester, 'not-an-email', 'whatever');
      await tester.tap(button('Đăng nhập'));
      await tester.pump();
      expect(find.text('Email không hợp lệ.'), findsOneWidget);
      expect(session.authCalls, isEmpty);
    });

    testWidgets('after a 4002: the expired banner and the email prefilled', (tester) async {
      session
        ..lastEmail = 'phu@shellx.pro'
        ..signOutReasonValue = SignOutReason.revoked;
      await openLogin(tester);
      expect(find.text('Phiên đăng nhập đã hết hiệu lực. Hãy đăng nhập lại.'), findsOneWidget);
      expect(find.text('phu@shellx.pro'), findsOneWidget);
      expect(find.text('Dùng cùng tài khoản với ShellX trên máy tính.'), findsNothing);
    });

    testWidgets('after deleting the account: "Tài khoản đã được xóa."', (tester) async {
      session.signOutReasonValue = SignOutReason.accountDeleted;
      await openLogin(tester);
      expect(find.text('Tài khoản đã được xóa.'), findsOneWidget);
    });
  });

  group('create account', () {
    Future<void> openRegister(WidgetTester tester) async {
      await openLogin(tester);
      await tester.tap(find.text('Tạo tài khoản'));
      await tester.pumpAndSettle();
      expect(find.text('Một tài khoản cho điện thoại và mọi máy tính của bạn.'), findsOneWidget);
    }

    testWidgets('checked while typing; the button stays dimmed until valid', (tester) async {
      await openRegister(tester);
      expect(stateOf(tester, 'Tạo tài khoản'), ButtonState.disable);

      await fill(tester, 'not-an-email', 'short');
      expect(find.text('Email không hợp lệ.'), findsOneWidget);
      expect(find.text('Từ 8 đến 128 ký tự. Còn thiếu 3 ký tự.'), findsOneWidget);
      expect(stateOf(tester, 'Tạo tài khoản'), ButtonState.disable);

      await fill(tester, 'me@example.com', 'long enough');
      expect(find.text('Email không hợp lệ.'), findsNothing);
      expect(find.text('Từ 8 đến 128 ký tự.'), findsOneWidget);
      expect(stateOf(tester, 'Tạo tài khoản'), ButtonState.available);

      await tester.tap(button('Tạo tài khoản'));
      await tester.pumpAndSettle();
      expect(session.authCalls, [('register', 'me@example.com', 'long enough')]);
    });

    testWidgets('the relay\'s disposable-email answer stays under the email until it changes', (tester) async {
      await openRegister(tester);
      session.authError = const ApiException(status: 400, code: 'disposable_email', message: 'x');
      await fill(tester, 'ban@yopmail.com', 'long enough');
      await tester.tap(button('Tạo tài khoản'));
      await tester.pumpAndSettle();
      expect(find.text('Email tạm thời không dùng được. Hãy dùng email thật.'), findsOneWidget);
      expect(stateOf(tester, 'Tạo tài khoản'), ButtonState.disable);
      expect(popups.errors, isEmpty);

      await tester.enterText(find.byType(TextField).at(0), 'ban@example.com');
      await tester.pump();
      expect(find.text('Email tạm thời không dùng được. Hãy dùng email thật.'), findsNothing);
      expect(stateOf(tester, 'Tạo tài khoản'), ButtonState.available);
    });

    testWidgets('the terms line links both pages', (tester) async {
      await openRegister(tester);
      await tester.tap(find.text('Điều khoản'));
      await tester.tap(find.text('Chính sách quyền riêng tư'));
      expect(links.opened, [Uri.parse('https://shellx.pro/terms'), Uri.parse('https://shellx.pro/privacy')]);
    });
  });
}
```

`apps/mobile/test/app_test.dart` (the real `AppRouter`, guards, `SessionHolderImpl`, `SessionEnforcer` and `RootApp` over `FakeRelayHttp` and fake backends):

```dart
import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/core/router/auth_guard.dart';
import 'package:shellx_mobile/core/router/update_guard.dart';
import 'package:shellx_mobile/features/app/app.dart';
import 'package:shellx_mobile/features/app/font_licenses.dart';
import 'package:shellx_mobile/features/app/launch.dart';
import 'package:shellx_mobile/features/auth/presentation/controllers/login_controller.dart';
import 'package:shellx_mobile/features/auth/presentation/controllers/register_controller.dart';
import 'package:shellx_mobile/features/lock/presentation/app_lock_controller.dart';
import 'package:shellx_mobile/features/machines/presentation/controllers/machine_list_controller.dart';
import 'package:shellx_mobile/features/pairing/presentation/controllers/qr_scanner_controller.dart';
import 'package:shellx_mobile/features/settings/presentation/controllers/delete_account_controller.dart';
import 'package:shellx_mobile/features/settings/presentation/controllers/settings_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_page_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';
import 'package:shellx_mobile/shared/shared.dart';

import 'support/fake_biometrics.dart';
import 'support/fake_links.dart';
import 'support/fake_popup_handler.dart';
import 'support/fake_relay_http.dart';
import 'support/fakes.dart';

/// The whole app with the real router, guards, SessionHolder and SessionEnforcer; only the relay
/// HTTP API, the backend (shellx_client), biometrics and toasts are fakes.
void main() {
  late FakeRelayHttp relay;
  late InMemoryKeyValueStore store;
  late FakeBackendFactory backends;
  late FakeBiometricAuthenticator biometrics;
  late FakePopupHandler popups;
  late FakeExternalLinks links;
  late AppSettings settings;
  late SessionHolderImpl session;
  late WorkspaceRegistry registry;
  late AppLockController lock;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // AdaptiveTheme (the base's theme switcher) reads its mode through SharedPreferencesAsync.
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    relay = FakeRelayHttp();
    store = InMemoryKeyValueStore();
    backends = FakeBackendFactory(
      () => FakeBackend(devices: [agentDevice(agentA, 'MacBook-Pro')], pinnedList: [pinned(agentA)])
        ..onlineIds.add(agentA)
        ..addMachine(agentA),
    );
    biometrics = FakeBiometricAuthenticator();
    popups = FakePopupHandler();
    links = FakeExternalLinks();
    final api = ShellxApi(baseUri: Uri.parse('http://127.0.0.1:8787'), httpClient: relay.client);
    final packageInfo = PackageInfo(
      appName: 'ShellX',
      packageName: 'pro.shellx.mobile',
      version: '1.0.0',
      buildNumber: '1',
    );
    final events = AuthEventNotifier();
    session = SessionHolderImpl(
      api: api,
      storage: AuthStorageImpl(store),
      store: store,
      device: const DeviceDescription(name: 'Pixel 8', platform: DevicePlatform.android),
      packageInfo: packageInfo,
      backends: backends,
      events: events,
    );
    final versionGate = VersionGate(api, packageInfo);
    settings = AppSettings(store);
    await settings.load();
    lock = AppLockController(authenticator: biometrics, isEnabled: () => settings.biometricLock.peek());
    registry = WorkspaceRegistry(session.backend);
    final router = AppRouter(authGuard: AuthGuard(session), updateGuard: UpdateGuard(versionGate));
    getIt
      ..registerSingleton<PopupHandler>(popups)
      ..registerSingleton<ExternalLinks>(links)
      ..registerSingleton<VersionGate>(versionGate)
      ..registerSingleton<SessionHolder>(session)
      ..registerSingleton<AppLockController>(lock)
      ..registerSingleton<AppRouter>(router)
      ..registerFactory<LoginController>(() => LoginController(session))
      ..registerFactory<RegisterController>(() => RegisterController(session))
      ..registerFactory<MachineListController>(() => MachineListController.create(session, registry))
      ..registerFactoryParam<TerminalPageController, String, void>(
        (agentId, _) => TerminalPageController(agentId, registry, session, settings),
      )
      ..registerFactory<QrScannerController>(() => QrScannerController(session))
      ..registerFactory<SettingsController>(
        () => SettingsController(session, settings, lock, biometrics, registry, packageInfo),
      )
      ..registerFactory<DeleteAccountController>(() => DeleteAccountController(session));
    SessionEnforcerImpl(events, router).initialize();
  });

  tearDown(() async {
    registry.dispose();
    await getIt.reset();
  });

  /// What `SplashPage` does after `configureDependencies()`, then the app itself.
  Future<void> launch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await prepareLaunch();
    await tester.pumpWidget(
      AdaptiveTheme(
        light: ThemeDataFactory.create(Brightness.light),
        dark: ThemeDataFactory.create(Brightness.dark),
        initial: AdaptiveThemeMode.light,
        builder: (light, dark) => const RootApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> signIn(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).at(0), 'me@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'correct horse');
    await tester.tap(find.widgetWithText(AppButton, 'Sign in'));
    await tester.pumpAndSettle();
  }

  testWidgets('an outdated app is blocked with the store link', (tester) async {
    relay.minMobile = '2.0.0';
    await launch(tester);
    expect(find.text('App update required'), findsOneWidget);
    expect(backends.backends, isEmpty); // the relay is never started
    await tester.tap(find.text('Open Google Play'));
    expect(links.opened, [Uri.parse('https://play.google.com/store/apps/details?id=pro.shellx.mobile')]);
  });

  testWidgets('a saved session opens the machine list directly', (tester) async {
    await AuthStorageImpl(store).save(
      const AccountSession(userId: testUserId, deviceId: testDeviceId, token: 'saved', email: 'me@example.com'),
    );
    await launch(tester);
    expect(find.text('Your computers'), findsOneWidget);
    expect(find.text('MacBook-Pro'), findsOneWidget);
  });

  testWidgets('sign in → machine list → settings → sign out returns to login', (tester) async {
    await launch(tester);
    expect(find.widgetWithText(AppButton, 'Sign in'), findsOneWidget);
    await signIn(tester);
    expect(find.text('Your computers'), findsOneWidget);
    expect(find.text('MacBook-Pro'), findsOneWidget);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppButton, 'Sign in'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
    expect(backends.backends.single.disposed, isTrue);
    expect(find.text('me@example.com'), findsOneWidget); // prefilled for the next sign-in
  });

  testWidgets('a revoked token while a terminal is open goes back to login (spec §12)', (tester) async {
    await launch(tester);
    await signIn(tester);
    await tester.tap(find.text('MacBook-Pro'));
    await tester.pumpAndSettle();
    expect(find.text('zsh 1'), findsOneWidget);

    backends.backends.single.emitRelay(RelayConnectionState.revoked);
    await tester.pumpAndSettle();
    expect(find.text('Your sign-in has expired. Please sign in again.'), findsOneWidget);
    expect(find.text('me@example.com'), findsOneWidget);
    expect(find.text('zsh 1'), findsNothing);
  });

  testWidgets('delete account from settings ends on the login screen', (tester) async {
    await launch(tester);
    await signIn(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'correct horse');
    await tester.pump();
    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();

    expect(find.text('Your account has been deleted.'), findsOneWidget);
    expect(await store.read(AuthStorage.tokenKey), isNull);
    expect(await store.read(DeviceIdentity.storageKey), isNull);
  });

  testWidgets('the lock screen covers the app on launch when enabled', (tester) async {
    biometrics.result = false;
    await launch(tester);
    expect(find.text('ShellX is locked'), findsOneWidget);
    biometrics.result = true;
    await tester.tap(find.text('Unlock with Face ID'));
    await tester.pumpAndSettle();
    expect(find.text('ShellX is locked'), findsNothing);
  });

  test('both font licences are registered for the licences page', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerFontLicenses();
    final packages = [await for (final entry in LicenseRegistry.licenses) ...entry.packages];
    expect(packages, containsAll(['JetBrains Mono', 'Raleway']));
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd apps/mobile && flutter test test/features/auth test/app_test.dart`
Expected: FAIL — `AuthFormValidator`, `LoginController`, `LoginRoute`, `AuthGuard`, `UpdateGuard`, `registerFontLicenses` are not defined.

- [ ] **Step 3: Validation and controllers**

`apps/mobile/lib/features/auth/domain/auth_form_validator.dart`:

```dart
import 'package:shellx_mobile/shared/shared.dart';
import 'package:shellx_mobile/utils/utils.dart' as utils;

/// Client-side checks before a request; the relay stays the authority (spec §5.2).
class AuthFormValidator {
  static const int minPasswordLength = 8;
  static const int maxPasswordLength = 128;

  /// Format only (the base's pragmatic regex); disposable domains are rejected by the relay.
  String? validateEmail(String? value) => utils.validateEmailWithMessages(
    value: value,
    requiredMessage: S.current.errorInvalidEmail,
    invalidMessage: S.current.errorInvalidEmail,
  );

  /// Sign-in: any stored password may be typed, only an empty one is refused.
  String? validatePassword(String? value) =>
      value == null || value.isEmpty ? S.current.validationPasswordRequired : null;

  /// Registration: spec §5.2 "8–128 ký tự" and nothing else (no case or digit rules).
  String? validateNewPassword(String? value) {
    final length = value?.length ?? 0;
    return length < minPasswordLength || length > maxPasswordLength ? S.current.errorWeakPassword : null;
  }
}
```

`apps/mobile/lib/features/auth/presentation/controllers/auth_controller.dart`:

```dart
import 'package:shellx_mobile/core/core.dart';

/// Shared by sign-in and registration. Success is routed by `SessionEnforcer`; failures show the
/// spec §12 texts ("Email hoặc mật khẩu không đúng.", "Thử lại sau ít phút.", …).
abstract class AuthController extends Controller {
  AuthController(this.sessionHolder);

  final SessionHolder sessionHolder;
  final Signal<bool> _busy = signal(false);
  bool _disposed = false;

  ReadonlySignal<bool> get busy => _busy;

  /// Prefills the email field with the last account on this phone.
  String? get lastEmail => sessionHolder.lastEmail;

  /// Why the user is back on this page (revoked, account deleted), shown above the form.
  SignOutReason? get signOutReason => sessionHolder.signOutReason.peek();

  Future<void> submit(String email, String password);

  Future<void> run(Future<void> Function() action) async {
    _busy.value = true;
    await guard(action);
    if (!_disposed) _busy.value = false;
  }

  void dispose() {
    _disposed = true;
    _busy.dispose();
  }
}
```

`apps/mobile/lib/features/auth/presentation/controllers/login_controller.dart`:

```dart
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/auth/presentation/controllers/auth_controller.dart';

@injectable
class LoginController extends AuthController {
  LoginController(super.sessionHolder);

  @override
  Future<void> submit(String email, String password) => run(() => sessionHolder.login(email, password));
}
```

`apps/mobile/lib/features/auth/presentation/controllers/register_controller.dart`:

```dart
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/auth/domain/auth_form_validator.dart';
import 'package:shellx_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Design "Tạo tài khoản": checked while typing (email format, 8–128 characters); the relay's
/// answers about the email (`invalid_email`, `disposable_email`, `email_taken`) or the password
/// (`weak_password`) stay under that field until it changes; the button is dimmed until valid.
@injectable
class RegisterController extends AuthController {
  RegisterController(super.sessionHolder);

  final AuthFormValidator _validator = AuthFormValidator();
  final Signal<String> _email = signal('');
  final Signal<String> _password = signal('');
  final Signal<({String email, String message})?> _emailRejected = signal(null);
  final Signal<({String password, String message})?> _passwordRejected = signal(null);

  late final Computed<String?> _emailError = computed(() {
    final email = _email.value.trim();
    final rejected = _emailRejected.value;
    if (rejected != null && rejected.email == email) return rejected.message;
    return email.isEmpty ? null : _validator.validateEmail(email);
  });

  late final Computed<String?> _passwordError = computed(() {
    final rejected = _passwordRejected.value;
    return rejected != null && rejected.password == _password.value ? rejected.message : null;
  });

  late final Computed<bool> _canSubmit = computed(
    () =>
        _email.value.trim().isNotEmpty &&
        _emailError.value == null &&
        _passwordError.value == null &&
        _validator.validateNewPassword(_password.value) == null &&
        !busy.value,
  );

  ReadonlySignal<String?> get emailError => _emailError;
  ReadonlySignal<String?> get passwordError => _passwordError;
  ReadonlySignal<String> get password => _password;
  ReadonlySignal<bool> get canSubmit => _canSubmit;

  void setEmail(String value) => _email.value = value;
  void setPassword(String value) => _password.value = value;

  /// "Từ 8 đến 128 ký tự. Còn thiếu 3 ký tự."
  String passwordHelp(S strings) {
    final length = _password.value.length;
    if (length > 0 && length < AuthFormValidator.minPasswordLength) {
      return '${strings.passwordRule} ${strings.passwordMissing(AuthFormValidator.minPasswordLength - length)}';
    }
    if (length > AuthFormValidator.maxPasswordLength) {
      return '${strings.passwordRule} ${strings.passwordTooLong(length - AuthFormValidator.maxPasswordLength)}';
    }
    return strings.passwordRule;
  }

  @override
  Future<void> submit(String email, String password) => run(() async {
    try {
      await sessionHolder.register(email, password);
    } on ApiException catch (error) {
      final message = ErrorText(S.current).api(error);
      switch (error.code) {
        case 'invalid_email' || 'disposable_email' || 'email_taken' when error.status != 429:
          _emailRejected.value = (email: email.trim(), message: message);
        case 'weak_password' when error.status != 429:
          _passwordRejected.value = (password: password, message: message);
        default:
          rethrow; // HTTP 429, network: a toast.
      }
    }
  });

  @override
  void dispose() {
    _canSubmit.dispose();
    _emailError.dispose();
    _passwordError.dispose();
    _email.dispose();
    _password.dispose();
    _emailRejected.dispose();
    _passwordRejected.dispose();
    super.dispose();
  }
}
```

- [ ] **Step 4: Login and register pages**

`apps/mobile/lib/features/auth/presentation/pages/login_page.dart`:

```dart
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/auth/domain/auth_form_validator.dart';
import 'package:shellx_mobile/features/auth/presentation/controllers/login_controller.dart';
import 'package:shellx_mobile/features/auth/presentation/widgets/password_text_field.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Spec §9.2 #1 and the design's "Đăng nhập": two fields, the forgot-password hint (passwords are
/// changed on a signed-in computer, spec §5.2), "Tạo tài khoản"; after a 4002 the banner
/// "Phiên đăng nhập đã hết hiệu lực. Hãy đăng nhập lại." with the email prefilled.
@RoutePage()
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _controller = getIt<LoginController>();
  final _validator = AuthFormValidator();
  late final _emailController = TextEditingController(text: _controller.lastEmail);
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (_formKey.currentState?.validate() ?? false) {
      await _controller.submit(_emailController.text, _passwordController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final colors = context.colors;
    final notice = switch (_controller.signOutReason) {
      SignOutReason.revoked => (strings.signedOutExpired, Icons.lock_outline),
      SignOutReason.accountDeleted => (strings.signedOutAccountDeleted, Icons.info_outline),
      SignOutReason.loggedOut || null => null,
    };
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 34, 20, 20),
                child: Form(
                  key: _formKey,
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Align(alignment: Alignment.centerLeft, child: ShellxLogo()),
                        22.sizedHeight,
                        Text(strings.loginTitle, style: context.typo.heading28.heavy),
                        if (notice == null) ...[
                          6.sizedHeight,
                          Text(
                            strings.loginSubtitle,
                            style: context.typo.subHeader15.copyWith(color: colors.secondaryText),
                          ),
                        ] else ...[
                          16.sizedHeight,
                          NoticeBanner(text: notice.$1, tone: NoticeTone.info, leading: Icon(notice.$2)),
                        ],
                        22.sizedHeight,
                        AppTextField(
                          label: strings.emailLabel,
                          hintText: strings.emailHint,
                          controller: _emailController,
                          validator: _validator.validateEmail,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                        ),
                        22.sizedHeight,
                        PasswordTextField(
                          label: strings.passwordLabel,
                          hintText: strings.passwordHint,
                          controller: _passwordController,
                          validator: _validator.validatePassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) => _handleSubmit(),
                        ),
                        22.sizedHeight,
                        Watch((context) {
                          return AppButton(
                            title: strings.loginButton,
                            state: _controller.busy.value ? ButtonState.loading : ButtonState.available,
                            onTap: _handleSubmit,
                          );
                        }),
                        16.sizedHeight,
                        Text(
                          strings.forgotPasswordHint,
                          textAlign: TextAlign.center,
                          style: context.typo.paragraph13.copyWith(color: colors.secondaryText),
                        ),
                        const Spacer(),
                        24.sizedHeight,
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(strings.noAccountPrompt, style: context.typo.subHeader15),
                            TextButton(
                              onPressed: () => context.router.push(const RegisterRoute()),
                              child: Text(
                                strings.createAccountLink,
                                style: context.typo.subHeader15.bold.copyWith(color: colors.primary),
                              ),
                            ),
                          ],
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
    );
  }
}
```

`apps/mobile/lib/features/auth/presentation/pages/register_page.dart`:

```dart
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/auth/presentation/controllers/register_controller.dart';
import 'package:shellx_mobile/features/auth/presentation/widgets/password_text_field.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Spec §9.2 #1 and the design's "Tạo tài khoản": errors under the field that is wrong, the
/// 8–128 hint with how many characters are missing, the button dimmed until valid, the terms line.
@RoutePage()
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _controller = getIt<RegisterController>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() => _controller.submit(_emailController.text, _passwordController.text);

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final colors = context.colors;
    final fine = context.typo.metadata12.copyWith(color: colors.disable, height: 1.5);
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(strings.registerTitle, style: context.typo.heading28.heavy),
                6.sizedHeight,
                Text(strings.registerSubtitle, style: context.typo.subHeader15.copyWith(color: colors.secondaryText)),
                20.sizedHeight,
                Watch(
                  (context) => AppTextField(
                    label: strings.emailLabel,
                    hintText: strings.emailHint,
                    controller: _emailController,
                    errorText: _controller.emailError.value,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    onChanged: _controller.setEmail,
                  ),
                ),
                20.sizedHeight,
                Watch(
                  (context) => PasswordTextField(
                    label: strings.passwordLabel,
                    hintText: strings.passwordHint,
                    controller: _passwordController,
                    errorText: _controller.passwordError.value,
                    helperText: _controller.passwordHelp(strings),
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.newPassword],
                    onChanged: _controller.setPassword,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                ),
                20.sizedHeight,
                Watch((context) {
                  final state = _controller.busy.value
                      ? ButtonState.loading
                      : _controller.canSubmit.value
                      ? ButtonState.available
                      : ButtonState.disable;
                  return AppButton(title: strings.registerButton, state: state, onTap: _submit);
                }),
                14.sizedHeight,
                HighlightedText(
                  strings.termsNotice(strings.termsLink, strings.privacyLink),
                  parts: {
                    strings.termsLink: () => getIt<ExternalLinks>().open(AppConfig.termsPage),
                    strings.privacyLink: () => getIt<ExternalLinks>().open(AppConfig.privacyPage),
                  },
                  textAlign: TextAlign.center,
                  style: fine,
                  partStyle: fine.copyWith(color: colors.primary, fontWeight: FontWeight.w700),
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

- [ ] **Step 5: Guards, routes and the session enforcer**

`apps/mobile/lib/core/router/auth_guard.dart`:

```dart
import 'package:auto_route/auto_route.dart';
import 'package:injectable/injectable.dart';
import 'package:shellx_mobile/core/auth/session_holder.dart';
import 'package:shellx_mobile/core/router/app_router.gr.dart';

/// Signed-in pages need a session (spec §9.2 #1).
@injectable
class AuthGuard extends AutoRouteGuard {
  final SessionHolder sessionHolder;

  AuthGuard(this.sessionHolder);

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    if (sessionHolder.isAuthenticated.peek()) {
      resolver.next(true);
    } else {
      router.replace(const LoginRoute());
      resolver.next(false);
    }
  }
}
```

`apps/mobile/lib/core/router/update_guard.dart`:

```dart
import 'package:auto_route/auto_route.dart';
import 'package:injectable/injectable.dart';
import 'package:shellx_mobile/core/router/app_router.gr.dart';
import 'package:shellx_mobile/core/version/version_gate.dart';

/// Spec §14: an app older than `min_mobile` shows only "Cần cập nhật app".
@injectable
class UpdateGuard extends AutoRouteGuard {
  final VersionGate versionGate;

  UpdateGuard(this.versionGate);

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    if (versionGate.requiredVersion.peek() == null) {
      resolver.next(true);
    } else {
      router.replace(const UpdateRequiredRoute());
      resolver.next(false);
    }
  }
}
```

`apps/mobile/lib/core/router/app_router.dart` (replace the whole file):

```dart
import 'package:auto_route/auto_route.dart';
import 'package:injectable/injectable.dart';
import 'package:shellx_mobile/core/router/app_router.gr.dart';
import 'package:shellx_mobile/core/router/auth_guard.dart';
import 'package:shellx_mobile/core/router/update_guard.dart';

@singleton
@AutoRouterConfig(replaceInRouteName: 'Screen|Page,Route')
class AppRouter extends RootStackRouter {
  final AuthGuard authGuard;
  final UpdateGuard updateGuard;

  AppRouter({required this.authGuard, required this.updateGuard});

  @override
  List<AutoRoute> get routes => [
    // Public routes; an outdated app is sent to UpdateRequiredRoute first.
    AutoRoute(page: UpdateRequiredRoute.page),
    AutoRoute(page: LoginRoute.page, guards: [updateGuard]),
    AutoRoute(page: RegisterRoute.page, guards: [updateGuard]),

    // Signed-in routes - MachineListRoute is initial.
    AutoRoute(page: MachineListRoute.page, initial: true, guards: [updateGuard, authGuard]),
    AutoRoute(page: TerminalRoute.page, guards: [authGuard]),
    AutoRoute(page: QrScannerRoute.page, guards: [authGuard]),
    AutoRoute(page: SettingsRoute.page, guards: [authGuard]),
    AutoRoute(page: DeleteAccountRoute.page, guards: [authGuard]),
  ];
}
```

`apps/mobile/lib/core/auth/session_enforcer.dart`:

```dart
import 'package:shellx_mobile/core/core.dart';

/// Routes on session changes (base pattern: [SessionHolder] emits, this class navigates):
/// a sign-in opens the machine list; a sign-out, a 4002 revocation or a deleted account
/// clears every page — terminal, settings, dialogs — and shows the login page.
abstract class SessionEnforcer {
  void initialize();
  void dispose();
}

@Singleton(as: SessionEnforcer)
class SessionEnforcerImpl implements SessionEnforcer {
  final AuthEventNotifier authEventNotifier;
  final AppRouter router;

  EventDisposer? _disposer;

  SessionEnforcerImpl(this.authEventNotifier, this.router);

  @override
  @postConstruct
  void initialize() {
    _disposer = authEventNotifier.addListener(
      AuthEventKeys.sessionEnforcer,
      (event) => switch (event) {
        SignedInEvent() => router.replaceAll([const MachineListRoute()]),
        SignedOutEvent() => router.replaceAll([const LoginRoute()]),
      },
      priority: EventPriority.high,
    );
  }

  @override
  @disposeMethod
  void dispose() {
    _disposer?.dispose();
  }
}
```

`apps/mobile/lib/core/core.dart` (replace the whole file):

```dart
export 'dependency/dependency.dart';
export 'design/app_colors.dart';
export 'design/dark_colors.dart';
export 'design/light_colors.dart';
export 'design/typography.dart';
export 'design/design_system.dart';
export 'design/theme_data_factory.dart';
export 'design/terminal_colors.dart';
export 'extensions/adaptive_theme_mode_x.dart';
export 'router/app_router.dart';
export 'architecture/error.dart';
export 'architecture/error_factory.dart';
export 'architecture/error_text.dart';
export 'architecture/controller.dart';
export 'architecture/state_signal.dart';
export 'handler/popup_handler.dart';
export 'architecture/page_domain.dart';
export 'architecture/paging_state_signal.dart';
export 'architecture/state.dart';
export 'router/app_router.gr.dart';
export 'handler/event_notifier.dart';
export 'router/app_transparent_route.dart';
export 'router/app_route_observer.dart';
// ShellX
export 'auth/account_session.dart';
export 'auth/auth_event.dart';
export 'auth/auth_storage.dart';
export 'auth/session_enforcer.dart';
export 'auth/session_holder.dart';
export 'backend/backend.dart';
export 'backend/client_backend.dart';
export 'config/app_config.dart';
export 'platform/device_description.dart';
export 'platform/external_links.dart';
export 'platform/fresh_install.dart';
export 'platform/secure_key_value_store.dart';
export 'settings/app_settings.dart';
export 'version/version_gate.dart';

// 3rd party
export 'package:auto_route/auto_route.dart';
export 'package:flutter/material.dart';
export 'package:get_it/get_it.dart';
export 'package:injectable/injectable.dart';
export 'package:signals_flutter/signals_flutter.dart';
export 'package:equatable/equatable.dart';
```

- [ ] **Step 6: Launch, root widget, `main()`; drop the placeholder page**

`apps/mobile/lib/features/app/launch.dart` (replace the whole file):

```dart
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/lock/presentation/app_lock_controller.dart';

/// Everything between dependency injection and the first route.
Future<void> prepareLaunch() async {
  // Spec §14: the version gate runs on every launch; an outdated app never starts the relay.
  final versionGate = getIt<VersionGate>();
  await versionGate.check();
  if (versionGate.requiredVersion.peek() == null) await getIt<SessionHolder>().restore();
  // Spec §5.6: locked when the app opens (if enabled).
  final lock = getIt<AppLockController>();
  await lock.detectKind();
  lock.lockOnLaunch();
}
```

`apps/mobile/lib/features/app/app.dart` (replace the whole file):

```dart
import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:toastification/toastification.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/lock/presentation/app_lock_controller.dart';
import 'package:shellx_mobile/features/lock/presentation/lock_gate.dart';
import 'package:shellx_mobile/shared/shared.dart';

class RootApp extends StatefulWidget {
  const RootApp({
    super.key,
  });

  @override
  State<RootApp> createState() => _RootAppState();
}

class _RootAppState extends State<RootApp> {
  //
  final appRouter = getIt<AppRouter>();
  final lock = getIt<AppLockController>();
  final session = getIt<SessionHolder>();

  @override
  Widget build(BuildContext context) {
    final computedBrightness = brightness;
    return ToastificationWrapper(
      config: const ToastificationConfig(
        alignment: Alignment.topCenter,
        animationDuration: Duration(milliseconds: 300),
      ),
      child: DesignSystem(
        typography: AppTypography.instance,
        appColors: computedBrightness.appColors,
        brightness: computedBrightness,
        child: MaterialApp.router(
          onGenerateTitle: (context) => S.of(context).appTitle,
          showSemanticsDebugger: false,
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            S.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          debugShowCheckedModeBanner: false,
          routerConfig: appRouter.config(
            navigatorObservers: () => [AppRouteObserver()],
          ),
          theme: ThemeDataFactory.create(computedBrightness),
          // Spec §5.6: the lock covers every route and dialog. Spec §9.4/§12: the relay is
          // suspended in the background and reconnected right away when the app comes back.
          builder: (context, child) => LockGate(
            lock: lock,
            onBackground: session.onBackground,
            onForeground: session.onForeground,
            child: child!,
          ),
        ),
      ),
    );
  }

  Brightness get brightness {
    return AdaptiveTheme.of(context).mode.brightness;
  }
}
```

`apps/mobile/lib/features/app/font_licenses.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Both bundled fonts are SIL OFL 1.1, whose text must ship with them (Settings → licences).
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['JetBrains Mono'], await rootBundle.loadString(Assets.licenses.jetBrainsMonoOFL));
    yield LicenseEntryWithLineBreaks(['Raleway'], await rootBundle.loadString(Assets.licenses.ralewayOFL));
  });
}
```

`apps/mobile/lib/main.dart` (replace the whole file):

```dart
import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:flutter/material.dart';
import 'package:shellx_mobile/core/design/theme_data_factory.dart';
import 'package:shellx_mobile/features/app/font_licenses.dart';
import 'features/app/splash_page.dart';

// No cryptography_flutter (coordinator ruling): shellx_core pins the pure-Dart
// X25519 / ChaCha20-Poly1305 / BLAKE2s backends that pass the Noise vectors.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  final themeMode = await AdaptiveTheme.getThemeMode() ?? AdaptiveThemeMode.system;
  runApp(
    AdaptiveTheme(
      light: ThemeDataFactory.create(Brightness.light),
      dark: ThemeDataFactory.create(Brightness.dark),
      initial: themeMode,
      builder: (lightTheme, darkTheme) {
        /// * [RootApp]
        return const SplashPage();
      },
    ),
  );
}
```

```bash
git rm -q apps/mobile/lib/features/app/start_page.dart
```

- [ ] **Step 7: Generate, run the new tests, analyze, run everything**

```bash
cd apps/mobile
dart run build_runner build
flutter test test/features/auth test/app_test.dart
flutter analyze
flutter test
```

Expected: `build_runner` drops `StartRoute` and adds `LoginRoute`, `RegisterRoute`, `MachineListRoute`, `UpdateRequiredRoute` routes and the guard, controller and enforcer registrations; `+18: All tests passed!`; `No issues found!`; `+334: All tests passed!`.

- [ ] **Step 8: Commit**

```bash
git add apps/mobile
git commit -m "feat(mobile): login and register, guards, session enforcer, launch and main"
```

- [ ] **Step 9: Build both platforms; generated code stays fresh**

```bash
cd apps/mobile
flutter build apk --debug
flutter build ios --simulator --debug   # macOS with Xcode only
dart run intl_utils:generate && dart run build_runner build
git status --short -- .
```

Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`; `✓ Built build/ios/iphonesimulator/Runner.app`; `git status` prints only `?? ios/Podfile.lock` (CocoaPods writes it on the first iOS build; nothing else may change — the platform files of Task 1 already carry Flutter 3.41's UIScene migration). Optional spot checks of the built artefacts:

```bash
grep -oE 'package="[^"]+"|minSdkVersion="26"' "$(find build/app/intermediates -name AndroidManifest.xml -path '*merged_manifest*' | head -1)" | sort -u
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" -c "Print :MinimumOSVersion" -c "Print :CFBundleDisplayName" build/ios/iphonesimulator/Runner.app/Info.plist
```

Expected: `package="pro.shellx.mobile"`, `minSdkVersion="26"`; `pro.shellx.mobile`, `15.0`, `ShellX`.

Commit the lock file like `apps/desktop/macos/Podfile.lock`:

```bash
git add apps/mobile/ios/Podfile.lock
git commit -m "build(mobile): commit the CocoaPods lock file"
```

---

## Manual verification on real devices (after Task 19)

These cannot be exercised by `flutter test`. Run the app against staging (`flutter run --release --dart-define=SHELLX_RELAY=https://relay-staging.shellx.pro`) with a desktop agent (plan 04) signed in to the same account, on at least one iPhone (iOS 15+) and one Android 8.0 (API 26) device or emulator plus a current Android phone. Compare every screen with `docs/superpowers/design/2026-09-25-shellx-mobile-ui.html` in both light and dark mode.

1. **Biometric lock:** Face ID / fingerprint prompt on cold start; the button names the method ("Mở khóa bằng Face ID"); passcode fallback works; background 4 min → no prompt, 6 min → prompt; Android 8.0 BiometricPrompt shows without crashing (AppCompat theme + `FlutterFragmentActivity`); switch disabled on a device without passcode.
2. **Camera and pairing:** permission prompt text; the scan line moves (and stays still with Reduce Motion on); scanning the desktop QR pairs in < 3 s and shows "Đã ghép nối" with the computer's name; "Mở terminal" opens it; denying the permission shows the text and "Mở Cài đặt" opens the app's settings; a QR from another account shows "Máy này không thuộc tài khoản của bạn…" in the sheet; an expired code shows "Mã QR không hợp lệ hoặc đã hết hạn…".
3. **Soft keyboards:** iOS keyboard and Gboard/Samsung keyboard: letters, Vietnamese Telex/VNI composition, Backspace (`deleteDetection`), Return (CR); `Ctrl` then `c` interrupts `sleep 100` (the key shows the outline while armed); double-tap `Ctrl` (filled with a dot) and type `a`, `e`; `Alt` then `b` moves a word back in bash.
4. **Full-screen programs:** `vim`, `htop`, `less`: arrows, Home/End, PgUp/PgDn, Esc, `Ctrl+Alt+←`; box-drawing characters render in JetBrains Mono; the `--t-*` colours match the design; emoji fall back.
5. **Hardware keyboard:** iPad + Magic Keyboard and an Android phone + Bluetooth keyboard: arrows, `Ctrl+A` reaches tmux, `Ctrl+V` reaches vim, ⌘C/⌘V (iOS) and Ctrl+Shift+C/V (Android) copy/paste.
6. **Copy/paste:** long-press selects a word, dragging extends, "Sao chép" copies; pasting three lines into zsh with bracketed paste does not execute them; into `cat` they arrive as separate lines.
7. **Size:** pinch zoom and the "Aa" slider change the font size smoothly; rotating to landscape puts the name and tabs in one bar with the keyboard button; showing/hiding the keyboard updates `stty size` on the computer; no `resize 0x…` in agent logs.
8. **Background/foreground:** open two tabs, run `yes | head -c 300000 | tail -c 20; sleep 30; echo done`, background the app for 1 min (the app suspends the relay; the agent shows the channel dropped), return: the status line shows "Mất kết nối, đang thử lại…" briefly, tabs re-attach and show `done`; open the same session on a second phone → the first phone shows "Phiên đang được mở trên thiết bị khác." and "Gắn lại" takes it back; `exit` in a tab keeps its output with "Phiên đã kết thúc", "Đóng tab" and "Mở phiên mới".
9. **Pure-Dart crypto performance (ruling):** on the oldest supported devices (an iOS 15 iPhone, an Android 8.0 phone) measure IK handshake time and keystroke echo latency in a release build; spec §1 target is < 150 ms median keystroke latency.
10. **Reinstall:** delete and reinstall on iOS → new device key → the machine shows "Chưa ghép nối" and must be paired again (spec §5.1).
11. **Account:** sign out → sign in again with the same account keeps pairings; another account on the same phone sees none; delete account from Settings (wrong password shows "Mật khẩu không đúng." under the field, the right password returns to login with "Tài khoản đã được xóa.", the desktop agent is signed out); revoke this phone's token from the desktop → the app returns to login with "Phiên đăng nhập đã hết hiệu lực. Hãy đăng nhập lại." and the email filled in.
12. **Update gate:** raise `MIN_MOBILE` on staging above the app version → "Cần cập nhật app" blocks the app and the button opens the store page of the platform (`--dart-define=SHELLX_APP_STORE_URL=…` in the release build once the App Store id exists).
13. **Touch targets and text size:** every tappable element is at least 44 pt (VoiceOver/TalkBack focus outlines); with the largest system text size the login, list, settings and terminal chrome still lay out without clipping.
