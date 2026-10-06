import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:win32/win32.dart' as win32;
import 'package:window_manager/window_manager.dart';

import 'l10n/app_localizations.dart';
import 'src/agent/agent_controller.dart';
import 'src/agent/agent_runtime.dart';
import 'src/agent/agent_state.dart';
import 'src/agent/desktop_services.dart';
import 'src/agent/notify_threshold.dart';
import 'src/agent/session_core.dart';
import 'src/config.dart';
import 'src/l10n/locale.dart';
import 'src/platform/app_reopen.dart';
import 'src/platform/attention_badge.dart';
import 'src/platform/desktop_notifications.dart';
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
import 'src/restore/restore_paths.dart';
import 'src/restore/restore_persistence.dart';
import 'src/restore/restore_store.dart';
import 'src/startup.dart';
import 'src/terminal/attention_announcer.dart';
import 'src/terminal/local_sessions_provider.dart';
import 'src/terminal/port_watch.dart';
import 'src/terminal/tab_attention.dart';
import 'src/terminal/terminal_tabs.dart';
import 'src/terminal_sharing/attach_throttle.dart';
import 'src/terminal_sharing/powershell.dart';
import 'src/terminal_sharing/sharing_paths.dart';
import 'src/terminal_sharing/terminal_sharing_setup.dart';
import 'src/ui/theme/font_licenses.dart';
import 'src/tray/tray_action.dart';
import 'src/tray/tray_actions.dart';
import 'src/tray/tray_menu.dart';
import 'src/tray/tray_presenter.dart';
import 'src/ui/activation.dart';
import 'src/ui/app.dart';
import 'src/ui/window_bounds.dart';
import 'src/ui/window_coordinator.dart';
import 'src/ui/window_focus.dart';
import 'src/ui/window_host.dart';
import 'src/ui/window_router.dart';

Future<void> main(List<String> args) async {
  // Spec §10.6: the Windows uninstaller runs `ShellX.exe
  // --terminal-sharing-cleanup` before deleting the files. No window, no
  // tray, no single-instance lock: remove the blocks, `bin` and `term`,
  // then exit.
  if (args.contains('--terminal-sharing-cleanup')) {
    exit(await _terminalSharingCleanup());
  }
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
  final supportDirectory = await getApplicationSupportDirectory();
  final lock = SingleInstanceLock(supportDirectory);
  if (!await lock.acquire()) {
    await lock.signalRunningInstance();
    exit(0);
  }
  startup.lock = lock;

  final settings = await SharedPrefsSettingsStore.open();
  late final ProviderContainer container;
  final windowHost = WindowManagerHost(
    // A1 D9: the close button hides the window; shells keep running.
    onCloseRequested: () =>
        container.read(windowRouterProvider.notifier).hideWindow(),
    bounds: WindowBoundsStore(settings),
    // A4 D25. The window is hidden until showTerminal() below, so no focus
    // event comes before the container exists.
    onFocusChanged: (focused) =>
        container.read(windowFocusProvider.notifier).set(focused),
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
  // A5a D2: the restore files. Logs carry error types only.
  final restoreStore = RestoreStore(
    Directory(
      restoreDirectoryPath(
        windows: Platform.isWindows,
        environment: environment,
        appSupportPath: supportDirectory.path,
      ),
    ),
    excludeFromBackup: Platform.isMacOS
        ? (path) async {
            await Process.run('/usr/bin/tmutil', ['addexclusion', path]);
          }
        : null,
    log: debugPrint,
  );
  await restoreStore.prepare();
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
  final sharingSetup = _terminalSharingSetup(
    environment,
    storedEnabled: settings.getBool(
      SettingKeys.terminalSharing,
      defaultValue: false,
    ),
  );

  final deviceName = deviceNameFromHostname(Platform.localHostname);
  // Push spec §7: the threshold is read from the settings whenever a command
  // ends, so the tray choice applies at once; titles start with the name the
  // relay knows this computer by.
  final pushNotifications = PushNotificationsSetup(
    threshold: () => notifyThreshold(settings),
    machineName: () => deviceName,
    locale: () => Platform.localeName,
    hooksDirectory: '${supportDirectory.path}${Platform.pathSeparator}hooks',
  );
  // The app's one ShellxApi: the controller sets its token at sign-in.
  final api = ShellxApi(baseUri: relayBase);
  // A1 D7: the process's one SessionManager. It outlives every runtime, so
  // signing out or losing the relay never ends a shell; Quit does.
  final core = SessionCore(
    ptyFactory: ptyFactory,
    shellResolver: PlatformShellResolver(
      operatingSystem: Platform.operatingSystem,
      environment: environment,
    ),
    homeDirectory: home,
    baseEnvironment: environment,
    api: api,
    notifications: pushNotifications,
    gitHeads: GitHeadReader(),
    portProbe: Platform.isWindows ? WindowsPortProbe() : MacPortProbe(),
  );

  // The process's one SecureKeyValueStore; DesktopServices builds the one
  // TrustedStore over it.
  final services = DesktopServices(
    secureStore: SecureKeyValueStore(),
    settings: settings,
    api: api,
    createApi: () => ShellxApi(baseUri: relayBase),
    runtimeFactory: (params) => CoreAgentRuntime(
      params,
      core: core,
      relayBaseUri: relayBase,
      appVersion: info.version,
      termEndpointPath: sharingSetup == null
          ? null
          : termEndpointPath(
              environment: environment,
              windows: Platform.isWindows,
            ),
    ),
    sessions: core.sessions,
    keepAwake: Platform.isWindows ? WindowsKeepAwake() : CaffeinateKeepAwake(),
    launchAtLogin: PackageLaunchAtLogin(),
    notifier: notifier,
    urlOpener: SystemUrlOpener(),
    l10n: l10n,
    appVersion: info.version,
    platform: Platform.isWindows
        ? DevicePlatform.windows
        : DevicePlatform.macos,
    deviceName: deviceName,
    // Sign-out and quit wait (at most 3 s) for PTY tree kills in flight.
    awaitPtyKills: ptyFactory.killsSettled,
    terminalSharing: sharingSetup,
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
    overrides: [
      desktopServicesProvider.overrideWithValue(services),
      homeDirectoryProvider.overrideWithValue(home),
      restoreStoreProvider.overrideWithValue(restoreStore),
    ],
  );

  // A4 D25: the focus the window has now; events keep it current.
  try {
    container
        .read(windowFocusProvider.notifier)
        .set(await windowManager.isFocused());
  } catch (error) {
    debugPrint('ShellX: reading the window focus failed: ${error.runtimeType}');
  }

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
    _unawaitedLogged(
      trayPresenter.render(next, local: container.read(trayLocalStateProvider)),
      'tray',
    );
    coordinateWindows(
      previous,
      next,
      container.read(windowRouterProvider.notifier),
    );
  }, fireImmediately: true);
  // A5a D13: the "Terminal" submenu follows the switch and the saved text.
  container.listen<TrayLocalState>(
    trayLocalStateProvider,
    (_, local) => _unawaitedLogged(trayPresenter.renderLocal(local), 'tray'),
  );

  // A1 D11: a second launch (Windows, `open -n`; activationRequests
  // coalesces watcher events into one request per launch), a macOS reopen
  // (Finder, Spotlight, Dock) and the tray all show the terminal window.
  void activate() => unawaited(handleActivation(container));
  lock.activationRequests().listen(
    (_) => activate(),
    onError: (Object error) =>
        debugPrint('ShellX: activation watch failed: ${error.runtimeType}'),
  );
  if (Platform.isMacOS) {
    listenForAppChannel(
      onReopen: activate,
      // ⌘Q / app menu Quit (A1 D10): the same flow as the tray's "Thoát".
      onQuitRequested: () => unawaited(trayActions.handle(const Quit())),
    );
  }
  listenForWindowTitle(
    container: container,
    host: windowHost,
    l10n: l10n,
    run: (call) => _unawaitedLogged(call, 'window title'),
  );
  listenForPortWatch(container: container, sessions: core.sessions);

  // A4: tab attention — system notifications (D14–D16), Dock/taskbar
  // badge (D18–D19), screen-reader announcements (D24). Reading the
  // attention provider here builds it before the first shell starts. None
  // of this needs a signed-in account (N1).
  final desktopNotifications = DesktopNotifications(
    notifier: notifier,
    settings: settings,
    l10n: l10n,
    onOpen: (id) => openTabFromNotification(
      container,
      id,
      activateApp: Platform.isMacOS
          ? () => _unawaitedLogged(activateMacApp(), 'activate')
          : null,
    ),
    viewOf: (id) => attentionView(container, id),
  );
  listenForDesktopNotifications(
    container: container,
    notifications: desktopNotifications,
    l10n: l10n,
  );
  listenForAttentionBadge(
    container: container,
    // macOS: after the window's queued show, which sets the Dock policy
    // (A1 D10) the badge needs.
    host: Platform.isMacOS
        ? AfterWindowBadge(
            const MacDockBadge(),
            windowSettled: windowPresenter.settled,
          )
        : Platform.isWindows
        ? const WindowsTaskbarBadge()
        : const NoBadge(),
    l10n: l10n,
    run: (call) => _unawaitedLogged(call, 'badge'),
  );
  final announcer = AttentionAnnouncer(
    l10n: l10n,
    announce: (text) {
      final view = PlatformDispatcher.instance.implicitView;
      if (view == null) return;
      _unawaitedLogged(
        SemanticsService.sendAnnouncement(view, text, TextDirection.ltr),
        'announcement',
      );
    },
  );
  listenAttention(
    container,
    onArrival: (a) {
      final tabs = container.read(terminalTabsProvider);
      final tab = tabs.tabs.where((t) => t.id == a.tabId).firstOrNull;
      if (tab == null) return;
      final view = attentionView(container, a.tabId);
      announcer.arrived(
        a,
        // Final ruling m-6: the pane that sent it, in a split tab.
        tab: tab.noticeLabel(a.paneId),
        windowFocused: view.windowFocused,
        tabSelected: view.tabSelected,
      );
    },
  );

  registerFontLicenses();
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: ShellxDesktopApp(locale: locale),
    ),
  );
  container.read(windowRouterProvider.notifier).showTerminal();
  // The only bootstrap() call. An unreadable keychain does not throw: the
  // controller starts signed out and notifies.
  await container.read(agentControllerProvider.notifier).bootstrap();
  // D11: every start opens the terminal window with a tab, sized to the
  // laid-out pane. After the bootstrap, so a signed-out strip is already
  // laid out and the new shell is not resized right after it starts.
  await WidgetsBinding.instance.endOfFrame;
  await handleActivation(container);
}

/// Spec §7.6, §12: the switch is offered on macOS, and on Windows only with
/// `SHELLX_EXPERIMENTAL=terminal-sharing`. Null otherwise (or without the
/// environment variables the paths need).
TerminalSharingSetup? _terminalSharingSetup(
  Map<String, String> environment, {
  required bool storedEnabled,
}) {
  final available = terminalSharingAvailable(
    macos: Platform.isMacOS,
    windows: Platform.isWindows,
    environment: environment,
    storedEnabled: storedEnabled,
  );
  if (!available) return null;
  return _anyTerminalSharingSetup(environment);
}

/// Regardless of the experimental flag (the uninstaller must always clean
/// up).
TerminalSharingSetup? _anyTerminalSharingSetup(
  Map<String, String> environment,
) {
  final paths = SharingPaths.forPlatform(
    windows: Platform.isWindows,
    environment: environment,
    executable: Platform.resolvedExecutable,
  );
  if (paths == null) return null;
  return TerminalSharingSetup(
    paths: paths,
    powerShell: Platform.isWindows
        ? PowerShellProbe(environment: environment)
        : null,
  );
}

/// Exit code of `--terminal-sharing-cleanup`: 0, or 1 when something was
/// left behind (the uninstaller goes on either way).
Future<int> _terminalSharingCleanup() async {
  try {
    final setup = _anyTerminalSharingSetup(Platform.environment);
    if (setup == null) return 1;
    // The profiles an enable remembered, in case PowerShell no longer
    // reports one (best effort: the settings need the plugin channel).
    var known = const <String>[];
    try {
      WidgetsFlutterBinding.ensureInitialized();
      known = (await SharedPrefsSettingsStore.open()).getStrings(
        SettingKeys.terminalSharingFiles,
      );
    } catch (error) {
      debugPrint('ShellX: reading settings failed: ${error.runtimeType}');
    }
    final result = await setup.cleanup(knownFiles: known);
    return result.complete ? 0 : 1;
  } catch (error) {
    debugPrint('ShellX: terminal sharing cleanup failed: ${error.runtimeType}');
    return 1;
  }
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
