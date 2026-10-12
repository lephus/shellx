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
import 'package:win32/win32.dart' as win32;
import 'package:window_manager/window_manager.dart';

import 'daemon_main.dart' as daemon;
import 'l10n/app_localizations.dart';
import 'src/agent/agent_controller.dart';
import 'src/agent/agent_side.dart';
import 'src/agent/agent_state.dart';
import 'src/agent/desktop_services.dart';
import 'src/agent/remote_agent_controller.dart';
import 'src/agent/ui_services.dart';
import 'src/remote/remote_shutdown.dart';
import 'src/remote/remote_tools_provider.dart';
import 'src/remote/ssh_reconnector.dart';
import 'src/cli/agent_marks.dart';
import 'src/cli/cli_install.dart';
import 'src/cli/cli_install_windows.dart';
import 'src/cli/cli_service.dart';
import 'src/cli/ui_command_handler.dart';
import 'src/config.dart';
import 'src/config/config_controller.dart';
import 'src/l10n/locale.dart';
import 'src/mux/background_service_choice.dart';
import 'src/mux/daemon_launcher.dart';
import 'src/mux/daemon_spawn.dart';
import 'src/mux/daemon_state.dart';
import 'src/mux/launch_mode.dart';
import 'src/mux/mux_lock.dart';
import 'src/mux/mux_paths.dart';
import 'src/mux/ui_mux_responder.dart';
import 'src/mux/windows_pipe_transport.dart';
import 'src/platform/app_reopen.dart';
import 'src/platform/attention_badge.dart';
import 'src/platform/desktop_notifications.dart';
import 'src/platform/global_hotkey.dart';
import 'src/platform/ime_trace.dart';
import 'src/platform/notifier.dart';
import 'src/platform/pty/flutter_pty_factory.dart';
import 'src/platform/settings_store.dart';
import 'src/platform/single_instance.dart';
import 'src/platform/system_info.dart';
import 'src/platform/terminal_problem_notifier.dart';
import 'src/platform/wake_detector.dart';
import 'src/restore/restore_paths.dart';
import 'src/restore/restore_persistence.dart';
import 'src/restore/restore_store.dart';
import 'src/platform/backup_exclusion.dart';
import 'src/startup.dart';
import 'src/terminal/attention_announcer.dart';
import 'src/terminal/clipboard_media.dart' show pasteImageStoreProvider;
import 'src/terminal/local_sessions_provider.dart';
import 'src/terminal/paste_image_store.dart'
    show PasteImageStore, startPasteImageSweeps;
import 'src/terminal/port_watch.dart';
import 'src/terminal/tab_attention.dart';
import 'src/terminal/terminal_tabs.dart';
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

// The headless `shellx-mux` entry point (A5b D2/D3). The native runners start
// the engine with entrypoint `daemonMain`, which the engine only looks up in
// this root library (an `export` is not found), so it forwards from here.
@pragma('vm:entry-point')
Future<void> daemonMain() => daemon.daemonMain();

Future<void> main(List<String> args) async {
  // Spec §10.6: the Windows uninstaller runs `ShellX.exe
  // --terminal-sharing-cleanup` before deleting the files. No window, no
  // tray, no single-instance lock: remove the blocks, `bin` and `term`,
  // then exit.
  if (parseLaunchMode(args) == LaunchMode.terminalSharingCleanup) {
    exit(await _terminalSharingCleanup());
  }
  WidgetsFlutterBinding.ensureInitialized();
  ImeTrace.installFrom(Platform.environment);
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
    start: () => _start(startup),
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

Future<void> _start(_Startup startup) async {
  // Spec §8.2: only one agent at a time.
  final supportDirectory = await getApplicationSupportDirectory();
  final lock = SingleInstanceLock(supportDirectory);
  if (!await lock.acquire()) {
    await lock.signalRunningInstance();
    exit(0);
  }
  startup.lock = lock;

  final settings = await SharedPrefsSettingsStore.open();
  // A12 D19: from here on, the language the user chose (the dialogs above
  // and the startup-failure ones keep the system language: the choice is
  // not readable yet, or something failed before it could be used).
  final locale = resolveAppLocale(
    PlatformDispatcher.instance.locales,
    override: appLanguageOverride(settings),
  );
  final l10n = lookupAppLocalizations(locale);
  late final ProviderContainer container;
  WakeDetector? sshWake;
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
  // A5a D2: the restore files. Logs carry error types only. Without a
  // place for them (Windows with no LOCALAPPDATA) nothing is saved or
  // restored, and the app starts as before.
  RestoreFiles restoreFiles;
  try {
    restoreFiles = RestoreStore(
      Directory(
        restoreDirectoryPath(
          windows: Platform.isWindows,
          environment: environment,
          appSupportPath: supportDirectory.path,
        ),
      ),
      excludeFromBackup: Platform.isMacOS ? excludeFromBackupMacOS : null,
      log: debugPrint,
    );
  } on StateError catch (error) {
    debugPrint('ShellX: no restore directory: ${error.runtimeType}');
    restoreFiles = const NullRestoreFiles();
  }
  await restoreFiles.prepare();
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
  final sharingSetup = terminalSharingSetupFor(
    environment,
    storedEnabled: settings.getBool(
      SettingKeys.terminalSharing,
      defaultValue: false,
    ),
  );

  final deviceName = deviceNameFromHostname(Platform.localHostname);
  // A7: the command line. Its folder, and — once its host listens — the
  // host's address and this launch's token go into every ShellX shell's
  // environment (D8, D29, amendment), so they are known before the first
  // shell. Without them (no HOME / LOCALAPPDATA) the app runs without the
  // command line.
  final cli = cliSetup(environment);
  // A7 C1, final ruling M1: the host listens before the sessions exist, so
  // a shell is only told of a host that runs. The single-instance lock is
  // held; the host also takes `mux/mux.lock`. Requests wait for the window
  // (attach, below).
  // A5b ruling: the whole background service sits behind the "Giữ shell
  // chạy khi đóng cửa sổ" switch (off by default). Off, this process owns
  // the shells, the agent and the command-line host, exactly as before. On
  // (or a service with sessions still running), the window attaches and the
  // service hosts all of that: never two hosts (R3).
  final responder = UiMuxResponder();
  DaemonLauncher? launcher;
  if (cli != null) {
    launcher = DaemonLauncher(
      transport: Platform.isWindows
          ? WindowsPipeTransport()
          : UnixMuxTransport(),
      endpoint: MuxEndpointFile(cli.mux.endpoint),
      daemonLockFree: () => MuxLock.isFree(cli.mux),
      spawn: () => spawnDaemon(version: info.version),
      appVersion: info.version,
      onRequest: responder.onRequest,
    );
  }
  final daemonMode =
      launcher != null &&
      await attachThisLaunch(
        enabled: backgroundServiceEnabled(settings),
        daemonLockFree: () => MuxLock.isFree(cli!.mux),
        findRunning: launcher.findRunning,
        quit: (client) => _quitService(client, cli!.mux),
      );
  CliService? cliService;
  if (cli != null && !daemonMode) {
    try {
      cliService = await CliService.listen(
        paths: cli.mux,
        cliPaths: cli.paths,
        settings: settings,
        appVersion: info.version,
        token: cli.token,
      );
    } catch (error) {
      debugPrint('ShellX: command-line host failed: ${error.runtimeType}');
    }
  }
  // A8: ssh and tmux resolved once; never a host in the log (D37).
  final remoteTools = await resolveRemoteToolsSafe(
    () => resolveRemoteTools(
      operatingSystem: Platform.operatingSystem,
      environment: environment,
      log: (message) => debugPrint('ShellX ssh: $message'),
    ),
  );
  // D20: the first step of Quit: no retry may start from here on.
  void stopRemoteRetries() {
    sshWake?.stop();
    container.read(sshReconnectorProvider.notifier).stop();
  }

  // Runs after the shutdown. Each step is bounded, so quitting always ends
  // in exit(0).
  Future<void> quitApp() async {
    // A11 D22: the global shortcut goes first, so nothing toggles a window
    // that is being torn down. The system drops it with the process anyway.
    await runBounded(
      () => container.read(globalHotkeyBinderProvider).dispose(),
      timeout: _quitStepTimeout,
      label: 'removing the global shortcut',
    );
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
  }

  // A10 D15: pasted images go with the shells (in-process quit, "Quit
  // completely"), never when the background service keeps them.
  Future<void> deletePastedImages() =>
      container.read(pasteImageStoreProvider).deleteAll();

  final AgentSide? side;
  final DesktopServices services;
  if (daemonMode) {
    side = null;
    services = buildUiServices(
      settings: settings,
      notifier: notifier,
      l10n: l10n,
      appVersion: info.version,
      relayBase: relayBase,
      deviceName: deviceName,
      sharingSetup: sharingSetup,
      windows: Platform.isWindows,
      stopRemoteRetries: stopRemoteRetries,
      // "Thoát": only this window's forwards end; the service keeps the
      // masters ("Thoát hoàn toàn" ends them there).
      shutdownRemote: () => cancelUiForwards(remoteTools),
      quitApp: quitApp,
      deletePastedImages: deletePastedImages,
    );
  } else {
    side = buildAgentSide(
      environment: environment,
      home: home,
      supportDirectory: supportDirectory.path,
      settings: settings,
      notifier: notifier,
      ptyFactory: ptyFactory,
      l10n: l10n,
      appVersion: info.version,
      relayBase: relayBase,
      sharingSetup: sharingSetup,
      deviceName: deviceName,
      remoteTools: remoteTools,
      cliPaths: cli?.paths,
      cliSocket: cliService?.address,
      cliToken: cli?.token,
      stopRemoteRetries: stopRemoteRetries,
      quitApp: quitApp,
      deletePastedImages: deletePastedImages,
    );
    services = side.services;
  }

  // A10 D15: pasted images live 24 h at most: swept now and every hour.
  final pasteImages = PasteImageStore(
    supportDirectory,
    excludeFromBackup: Platform.isMacOS ? excludeFromBackupMacOS : null,
  );
  startPasteImageSweeps(pasteImages);

  container = ProviderContainer(
    overrides: [
      desktopServicesProvider.overrideWithValue(services),
      remoteToolsProvider.overrideWithValue(remoteTools),
      homeDirectoryProvider.overrideWithValue(home),
      pasteImageStoreProvider.overrideWithValue(pasteImages),
      restoreStoreProvider.overrideWithValue(restoreFiles),
      if (daemonMode) ...[
        daemonModeProvider.overrideWithValue(true),
        daemonConnectorProvider.overrideWithValue(launcher),
        uiMuxResponderProvider.overrideWithValue(responder),
        // The agent is the service's: each new connection rebuilds it.
        agentControllerProvider.overrideWith(
          () => RemoteAgentController.lazy(
            () => container.read(daemonLinkProvider)?.client,
          ),
        ),
      ],
      if (cli != null) ...[
        cliMuxPathsProvider.overrideWithValue(cli.mux),
        cliPathsProvider.overrideWithValue(cli.paths),
        cliPathInstallerProvider.overrideWithValue(
          Platform.isWindows
              ? WindowsPathInstaller(
                  cli.paths,
                  reg: WindowsUserEnvironment(),
                  broadcast: broadcastEnvironmentChange,
                )
              : MacPathInstaller(cli.paths),
        ),
        if (!Platform.isWindows)
          cliLoginPathCheckProvider.overrideWithValue(
            () => LoginPathCheck(
              shell: environment['SHELL'] ?? '/bin/zsh',
              linkDir: File(cli.paths.systemLink).parent.path,
            ).missing(),
          ),
      ],
    ],
  );

  // A9 D10: the configuration before the first frame and before the A5a
  // restore below (restored panes get the configured scrollback and font).
  // A few small local reads, bounded by the reader (FIFOs and devices are
  // refused) and by 1 s here: a slow disk finishes in the background and
  // applies when done. load() never throws.
  await runBounded(
    () => container.read(shellxConfigProvider.notifier).load(),
    timeout: const Duration(seconds: 1),
    label: 'reading the configuration',
  );
  container.read(shellxConfigProvider.notifier).startWatching();
  // A11 D22: the optional global show/hide shortcut, from the configuration
  // just loaded; off unless `global-hotkey` is set. Only this (UI) process
  // registers it, never the background service.
  container.read(globalHotkeyBinderProvider);

  // A4 D25: the focus the window has now; events keep it current.
  try {
    container
        .read(windowFocusProvider.notifier)
        .set(await windowManager.isFocused());
  } catch (error) {
    debugPrint('ShellX: reading the window focus failed: ${error.runtimeType}');
  }

  // A5a D16: the restore starts before anything can open a tab (the tray,
  // a second launch, a reopen, a notification): those wait for it instead
  // of opening a blank tab. Its panes open once the window is laid out
  // ([layoutReady]), so their grids come from the real area (D17).
  final restore = container.read(restorePersistenceProvider.notifier)..start();
  // A8 D20: lost SSH panes retry by themselves; a wake retries at once.
  container.read(sshReconnectorProvider);
  sshWake = WakeDetector(
    onWake: () => container.read(sshReconnectorProvider.notifier).onWake(),
  )..start();
  final layoutReady = Completer<void>();
  Future<RestoreLoad> loadForRestore() async {
    final load = await restoreFiles.loadLayout();
    await layoutReady.future;
    return load;
  }

  // With the background service the restore waits for the connection (the
  // snapshot is compared with the service instance), below.
  if (!daemonMode) {
    _unawaitedLogged(restore.restoreAtStartup(loadForRestore()), 'restore');
  }

  final windowPresenter = WindowPresenter(windowHost);
  container.listen<WindowState>(
    windowRouterProvider,
    (_, next) => _unawaitedLogged(windowPresenter.apply(next), 'window'),
    fireImmediately: true,
  );
  // The window hid (the close button, ⌘W on the empty state): save now,
  // not clean — the shells keep running.
  container.listen<bool>(windowRouterProvider.select((s) => s.visible), (
    previous,
    visible,
  ) {
    if (previous == true && !visible) {
      _unawaitedLogged(restore.flushAll(clean: false), 'restore save');
    }
  });

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
  // A5a I1: the Windows installer, updating a running ShellX, asks it to
  // quit — the same clean, final save as the Restart Manager's quit.
  lock.quitRequests().listen(
    (_) => unawaited(trayActions.handle(const Quit(confirm: false))),
    onError: (Object error) =>
        debugPrint('ShellX: quit watch failed: ${error.runtimeType}'),
  );
  // Both platforms: Windows sends only the three A5a calls.
  listenForAppChannel(
    onReopen: activate,
    // ⌘Q / app menu Quit (A1 D10): the same flow as the tray's "Thoát".
    onQuitRequested: () => unawaited(trayActions.handle(const Quit())),
    // A5a D18: log out, restart, shut down — a clean, final save.
    onSaveBeforeExit: () => runBounded(
      () => restore.flushAll(clean: true),
      timeout: _quitStepTimeout,
      label: 'saving before power-off',
    ),
    // The exit did not happen: saving goes on once the clean layout is on
    // disk (resume waits for it). A newer saveBeforeExit, or a committed
    // Quit, keeps it frozen.
    onExitCancelled: restore.resume,
    // Windows Restart Manager (D18 amended): saved; quit, nothing to ask.
    onQuitAfterSave: () =>
        unawaited(trayActions.handle(const Quit(confirm: false))),
    // A5b UI-A5 §6.1: ⌥⌘Q in the app menu.
    onQuitAllRequested: () => unawaited(trayActions.handle(const QuitAll())),
  );
  if (daemonMode && Platform.isMacOS) {
    _unawaitedLogged(setQuitAllTitle(l10n.appMenuQuitAll), 'app menu');
  }
  listenForWindowTitle(
    container: container,
    host: windowHost,
    l10n: l10n,
    run: (call) => _unawaitedLogged(call, 'window title'),
  );
  listenForPortWatch(container: container, sessions: side?.core.sessions);

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
    // Service mode: the service owns these two switches (D13).
    switches: daemonMode ? agentStateSwitches(container) : null,
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

  // A7 D27: "An agent is controlling {tab}", at most once a minute.
  container.read(agentMarksProvider.notifier).onAnnounce = (tabId) {
    final tab = container
        .read(terminalTabsProvider)
        .tabs
        .where((t) => t.id == tabId)
        .firstOrNull;
    final view = PlatformDispatcher.instance.implicitView;
    if (tab == null || view == null) return;
    _unawaitedLogged(
      SemanticsService.sendAnnouncement(
        view,
        l10n.cliAnnounceAgent(tab.label),
        TextDirection.ltr,
      ),
      'announcement',
    );
  };
  // D17 `--raise`: show and activate the window, without opening a tab.
  container.read(uiCommandHandlerProvider).onRaise = () async {
    container.read(windowRouterProvider.notifier).showTerminal();
    if (Platform.isMacOS) await activateMacApp();
  };
  // A7 C1: the window is up; the host's requests reach it now. Quit stops
  // the host first, before the shells close (tray Quit, ruling M6: attach
  // registers it in cliHostControlProvider).
  cliService?.attach(container);
  if (daemonMode && cli != null) {
    // The command line is the service's; the `shellx` command's folder is
    // still kept current from here.
    unawaited(
      CliBinaryInstaller(cli.paths).ensureCurrent().then(
        (_) {},
        onError: (Object e) =>
            debugPrint('ShellX: cli binary install failed: ${e.runtimeType}'),
      ),
    );
  }

  registerFontLicenses();
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: ShellxDesktopApp(locale: locale),
    ),
  );
  container.read(windowRouterProvider.notifier).showTerminal();
  if (daemonMode) {
    // UI-A5 §7.3, §7.4: the dialogs come over the window; leaving them is
    // leaving the window (nothing was started here, nothing to save).
    final link = await container
        .read(daemonStateProvider.notifier)
        .connectAtStartup();
    if (link == null) {
      await quitApp();
      return;
    }
    try {
      await container.read(agentControllerProvider.notifier).bootstrap();
    } catch (error) {
      debugPrint('ShellX: agent state not read: ${error.runtimeType}');
    }
    // A5b D14: the same service instance as the saved layout: reattach.
    _unawaitedLogged(
      restore.restoreAtStartup(loadForRestore(), daemonInstance: link.instance),
      'restore',
    );
  } else {
    // The only bootstrap() call. An unreadable keychain does not throw: the
    // controller starts signed out and notifies.
    await container.read(agentControllerProvider.notifier).bootstrap();
  }
  // D11: every start opens the terminal window with a tab, sized to the
  // laid-out pane. After the bootstrap, so a signed-out strip is already
  // laid out and the new shell is not resized right after it starts.
  await WidgetsBinding.instance.endOfFrame;
  // A5a D16: the restore reopens its panes now; the activation below waits
  // for it, so a restored window gets no extra tab.
  layoutReady.complete();
  await handleActivation(container);
}

/// The switch is off but a service with no sessions still runs from before:
/// it exits (its shells are none), and the lock frees, so this launch is
/// the one host (R3). Bounded; never throws.
Future<void> _quitService(MuxClient client, MuxPaths paths) async {
  try {
    await client
        .request(MuxType.daemonQuit)
        .timeout(const Duration(seconds: 4));
  } on Object {
    // Gone, or it did not answer: the lock below tells.
  }
  try {
    await client.close();
  } on Object {
    // Already closed.
  }
  final until = DateTime.now().add(const Duration(seconds: 5));
  while (!await MuxLock.isFree(paths) && DateTime.now().isBefore(until)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

/// Exit code of `--terminal-sharing-cleanup`: 0, or 1 when something was
/// left behind (the uninstaller goes on either way).
Future<int> _terminalSharingCleanup() async {
  try {
    final setup = anyTerminalSharingSetup(Platform.environment);
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
