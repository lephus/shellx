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

  // The close button hides the window to the tray (the router closes what
  // is open); it never quits the app.
  late final ProviderContainer container;
  final windowHost = WindowManagerHost(
    onCloseRequested: () =>
        container.read(windowRouterProvider.notifier).close(),
  );
  await windowHost.init();

  // `version` is the pubspec `version:` without `+build` (x.y.z), which
  // DesktopServices asserts and the update check requires.
  final info = await PackageInfo.fromPlatform();
  final environment = Map<String, String>.of(Platform.environment);
  final home =
      environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'] ??
      Directory.current.path;
  final relayBase = Uri.parse(kRelayBaseUrl);
  final notifier = await LocalSystemNotifier.setup();
  // A failed tree kill (or, on Windows, a shell without a job object) may
  // leave processes behind: log it and tell the user. The message holds a
  // pid and a reason only — never output, arguments or environment.
  final ptyFactory = FlutterPtyFactory.forCurrentPlatform(
    onError: (message) {
      FlutterPtyAdapter.debugPrintError(message);
      _unawaitedLogged(
        notifier.show(title: l10n.notifyTerminalProblemTitle, body: message),
        'terminal problem notification',
      );
    },
  );
  late final TrayManagerHost trayHost;

  // The process's one SecureKeyValueStore; DesktopServices builds the one
  // TrustedStore over it.
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
    // Sign-out and quit wait (at most 3 s) for PTY tree kills in flight.
    awaitPtyKills: ptyFactory.killsSettled,
    // Runs after AgentController.shutdown(); exits even if cleanup fails.
    quitApp: () async {
      try {
        await trayHost.destroy();
        await lock.release();
      } finally {
        exit(0);
      }
    },
  );

  container = ProviderContainer(
    overrides: [desktopServicesProvider.overrideWithValue(services)],
  );

  final windowPresenter = WindowPresenter(windowHost);
  container.listen<WindowState>(
    windowRouterProvider,
    (_, next) => _unawaitedLogged(windowPresenter.apply(next), 'window'),
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
    // Never throws (errors become a notification).
    onAction: trayActions.handle,
  );
  container.listen<AgentViewState>(agentControllerProvider, (previous, next) {
    _unawaitedLogged(trayPresenter.render(next), 'tray');
    coordinateWindows(
      previous,
      next,
      container.read(windowRouterProvider.notifier),
    );
  }, fireImmediately: true);

  // A second launch (double-click while running) asks us to come forward.
  lock.activationRequests().listen(
    (_) {
      final state = container.read(agentControllerProvider);
      if (!state.signedIn) {
        container.read(windowRouterProvider.notifier).open(const LoginRoute());
      } else {
        _unawaitedLogged(
          notifier.show(
            title: l10n.notifyAlreadyRunningTitle,
            body: l10n.notifyAlreadyRunningBody(
              Platform.isWindows ? 'windows' : 'macos',
            ),
          ),
          'already-running notification',
        );
      }
    },
    onError: (Object error) =>
        debugPrint('ShellX: activation watch failed: ${error.runtimeType}'),
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: ShellxDesktopApp(locale: locale),
    ),
  );
  // The only bootstrap() call.
  await container.read(agentControllerProvider.notifier).bootstrap();
}

/// Fire-and-forget for tray, window and notification calls: a failure is
/// logged by type (never with payloads) instead of becoming an unhandled
/// Future error.
void _unawaitedLogged(Future<void> future, String what) {
  unawaited(
    future.catchError(
      (Object error) =>
          debugPrint('ShellX: $what failed: ${error.runtimeType}'),
    ),
  );
}

void _windowsErrorBox(String message) {
  final text = message.toNativeUtf16();
  final title = 'ShellX'.toNativeUtf16();
  win32.MessageBox(0, text, title, win32.MB_OK | win32.MB_ICONERROR);
  malloc.free(text);
  malloc.free(title);
}
