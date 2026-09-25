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
import 'src/platform/terminal_problem_notifier.dart';
import 'src/platform/url_opener.dart';
import 'src/startup.dart';
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

  // Whatever fails from here on must not leave an invisible process holding
  // the single-instance lock (every later launch would exit silently).
  final startup = _Startup();
  await runGuardedStartup(
    start: () => _start(startup, locale, l10n),
    releaseLock: () async {
      await startup.lock?.release();
    },
    showError: () => _showStartupError(startup, l10n),
    exit: exit,
  );
}

/// How long each step of quitting may take before it is skipped.
const Duration _quitStepTimeout = Duration(seconds: 2);

/// What the failure path of [runGuardedStartup] needs from a start that
/// stopped halfway.
final class _Startup {
  SingleInstanceLock? lock;
  SystemNotifier? notifier;
}

Future<void> _start(
  _Startup startup,
  Locale locale,
  AppLocalizations l10n,
) async {
  // Spec §8.2: only one agent at a time.
  final lock = SingleInstanceLock(await getApplicationSupportDirectory());
  if (!await lock.acquire()) {
    await lock.signalRunningInstance();
    exit(0);
  }
  startup.lock = lock;

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
  final notifier = startup.notifier = await LocalSystemNotifier.setup();
  // A failed tree kill (or, on Windows, a shell without a job object) may
  // leave processes behind: the debug log gets the pid and the reason
  // (onError's default), the user one notification per burst with the pids
  // only — never output, arguments or environment.
  final terminalProblems = TerminalProblemNotifier(
    notifier: notifier,
    l10n: l10n,
  );
  final ptyFactory = FlutterPtyFactory.forCurrentPlatform(
    onProblem: terminalProblems.report,
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
    // Runs after AgentController.shutdown(). Each step is bounded, so
    // quitting always ends in exit(0).
    quitApp: () async {
      await runBounded(
        trayHost.destroy,
        timeout: _quitStepTimeout,
        label: 'removing the tray icon',
      );
      await runBounded(
        lock.release,
        timeout: _quitStepTimeout,
        label: 'releasing the lock',
      );
      exit(0);
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

  // A second launch (double-click while running) asks us to come forward;
  // one request per launch (activationRequests coalesces watcher events).
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
  // The only bootstrap() call. An unreadable keychain does not throw: the
  // controller starts signed out and notifies.
  await container.read(agentControllerProvider.notifier).bootstrap();
}

/// The app failed to start, so there may be no window or tray icon to show
/// the error in. Windows: a message box, like the version check. macOS:
/// best effort, a notification.
Future<void> _showStartupError(_Startup startup, AppLocalizations l10n) async {
  if (Platform.isWindows) {
    _windowsErrorBox(l10n.startupFailed);
    return;
  }
  final notifier = startup.notifier ?? await LocalSystemNotifier.setup();
  await notifier.show(title: 'ShellX', body: l10n.startupFailed);
  // Give the notification a moment to reach Notification Center before
  // the process exits.
  await Future<void>.delayed(const Duration(seconds: 1));
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
