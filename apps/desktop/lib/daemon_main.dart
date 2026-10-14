import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shellx_agent/shellx_agent.dart';

import 'l10n/app_localizations.dart';
import 'src/agent/agent_bridge_impl.dart';
import 'src/agent/agent_controller_base.dart';
import 'src/agent/agent_side.dart';
import 'src/agent/desktop_services.dart';
import 'src/cli/cli_host_control.dart';
import 'src/cli/cli_install.dart';
import 'src/config.dart';
import 'src/l10n/locale.dart';
import 'src/mux/daemon_host.dart';
import 'src/mux/mux_lock.dart';
import 'src/mux/mux_paths.dart';
import 'src/mux/windows_pipe_transport.dart';
import 'src/mux/windows_runtime_copy.dart';
import 'src/platform/notifier.dart';
import 'src/platform/pty/flutter_pty_factory.dart';
import 'src/platform/settings_store.dart';
import 'src/platform/system_info.dart';
import 'src/platform/terminal_problem_notifier.dart';
import 'src/remote/remote_tools_provider.dart';
import 'src/startup.dart';

/// What the daemon tells a client about itself (`hello.caps`, additive).
const kDaemonCaps = ['agent', 'cli'];

/// The `shellx-mux` entry point (A5b D2/D3): started by the native runner
/// on a headless engine, never through `main()`, so it takes no arguments.
///
/// Takes `mux/mux.lock` (held: another daemon runs, exit 0), builds what
/// the process owns (settings, shells, the agent with its relay, the
/// command-line host), serves them on the mux address and exits when
/// nothing needs it (D27) or on `daemon.quit`. Logs error types only.
@pragma('vm:entry-point')
Future<void> daemonMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  MuxLock? lock;
  try {
    final environment = Map<String, String>.of(Platform.environment);
    final paths = muxPathsFor(environment);
    try {
      lock = await MuxLock.acquire(paths);
    } on StateError {
      exit(0); // D16: a daemon runs already.
    }
    final info = await PackageInfo.fromPlatform();
    if (Platform.isWindows &&
        Platform.resolvedExecutable.toLowerCase().endsWith('shellx-mux.exe')) {
      final local = environment['LOCALAPPDATA'];
      if (local != null) {
        await cleanupOldRuntimes(localAppData: local, keep: info.version);
      }
    }
    await _serve(paths: paths, environment: environment, version: info.version);
  } catch (error) {
    debugPrint('ShellX daemon: stopped: ${error.runtimeType}');
    try {
      await lock?.release();
    } on Object {
      // The process ends next.
    }
    exit(1);
  }
}

Future<void> _serve({
  required MuxPaths paths,
  required Map<String, String> environment,
  required String version,
}) async {
  final locale = resolveAppLocale(PlatformDispatcher.instance.locales);
  final l10n = lookupAppLocalizations(locale);
  final supportDirectory = await getApplicationSupportDirectory();
  final settings = await SharedPrefsSettingsStore.open();
  final home =
      environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'] ??
      Directory.current.path;
  final notifier = await LocalSystemNotifier.setup();
  final ptyFactory = FlutterPtyFactory.forCurrentPlatform(
    onProblem: TerminalProblemNotifier(notifier: notifier, l10n: l10n).report,
  );
  final remoteTools = await resolveRemoteToolsSafe(
    () => resolveRemoteTools(
      operatingSystem: Platform.operatingSystem,
      environment: environment,
      log: (message) => debugPrint('ShellX ssh: $message'),
    ),
  );
  final token = generateCliToken();
  final cliPaths = CliPaths.forPlatform(
    windows: Platform.isWindows,
    environment: environment,
    executable: Platform.resolvedExecutable,
  );

  late final DaemonHost host;
  final side = buildAgentSide(
    environment: environment,
    home: home,
    supportDirectory: supportDirectory.path,
    settings: settings,
    notifier: notifier,
    ptyFactory: ptyFactory,
    l10n: l10n,
    appVersion: version,
    relayBase: Uri.parse(kRelayBaseUrl),
    sharingSetup: terminalSharingSetupFor(
      environment,
      storedEnabled: settings.getBool(
        SettingKeys.terminalSharing,
        defaultValue: false,
      ),
    ),
    deviceName: deviceNameFromHostname(Platform.localHostname),
    remoteTools: remoteTools,
    cliPaths: cliPaths,
    // The listener below is this daemon's: shells are told its address and
    // this launch's token, and open only after it listens.
    cliSocket: paths.address,
    cliToken: token,
    // There is no reconnector here (it is the UI's); nothing to stop.
    stopRemoteRetries: null,
    // The exit is the host's (idle or `daemon.quit`), after its shutdown.
    quitApp: () async {},
  );
  final core = side.core;
  final container = ProviderContainer(
    overrides: [desktopServicesProvider.overrideWithValue(side.services)],
  );

  final identity = newDaemonIdentity();
  final self = MuxPeerInfo(
    protocol: kMuxProtocol,
    app: version,
    instance: identity.instance,
    pid: pid,
    caps: kDaemonCaps,
  );
  final server = MuxServer(
    sessions: core.sessions,
    secret: identity.secret,
    self: self,
    agent: ControllerAgentBridge(container),
    onQuit: () => host.quit(),
    onUiChanged: (attached) => host.onUiChanged(attached),
  );
  // V2-2 D1: phones' AI messages go to the attached window that serves
  // AI; its pushes go out with this service's account.
  final aiForwarder = MuxAiForwarder(
    onPush: (push) => core.notifications?.aiNotice(push),
  );
  server.ai = aiForwarder;
  core.ai.target = aiForwarder;
  final cli = CliHost.adopted(
    ui: server.uiApi,
    enabled: () =>
        settings.getBool(SettingKeys.cliControlEnabled, defaultValue: true),
    token: token,
    allowExternal: () =>
        settings.getBool(SettingKeys.cliAllowExternal, defaultValue: false),
    appVersion: version,
    hostKind: () => 'daemon',
    uiAttached: () => server.uiAttached,
    log: (m) => debugPrint('ShellX daemon: $m'),
  );
  server.cli = cli;

  // D13: the agent changes a CLI switch and rechecks the open connections
  // itself, in this process.
  container.read(cliHostControlProvider).recheck = cli.recheck;

  bool servingPhones() {
    final state = container.read(agentControllerProvider);
    return state.signedIn && state.remoteAccess;
  }

  host = DaemonHost(
    server: server,
    endpoint: MuxEndpointFile(paths.endpoint),
    info: MuxEndpointInfo(
      address: paths.address,
      secret: identity.secret,
      pid: pid,
      instance: identity.instance,
      protocol: kMuxProtocol,
      app: version,
    ),
    // A connected `cli` client is not a UI, but it delays the idle exit.
    hasSessions: () => core.sessions.sessions.isNotEmpty || cli.clientCount > 0,
    servingPhones: servingPhones,
    shutdown: () => _shutdown(container, cli, side),
    exit: exit,
    log: (m) => debugPrint(m),
  );
  cli.onClientsChanged = host.onStateChanged;
  core.sessions.changes.listen((_) => host.onStateChanged());
  container.listen(agentControllerProvider, (_, _) => host.onStateChanged());

  final listener =
      await (Platform.isWindows ? WindowsPipeTransport() : UnixMuxTransport())
          .listen(paths.address);
  await host.start(listener);
  if (!Platform.isWindows) {
    // Logout and `kill` end the service like `daemon.quit`: shells closed
    // in order, the endpoint removed.
    ProcessSignal.sigterm.watch().listen((_) => unawaited(host.quit()));
  }
  // The listener is up: the relay and phones may open sessions now. An
  // unreadable keychain does not throw (the agent starts signed out).
  await container.read(agentControllerProvider.notifier).bootstrap();
  host.onStateChanged();
}

/// `daemon.quit` (A5b D14, R2): the command-line host stops first (ruling
/// M6), then every shell closes and the agent stops (`AgentController.
/// shutdown` also waits, bounded, for the PTY kills), then the remote side
/// goes: port probes, forwards, and every ssh master in the control
/// directory, the UI's included.
Future<void> _shutdown(
  ProviderContainer container,
  CliHost cli,
  AgentSide side,
) async {
  await runBounded(
    cli.stop,
    timeout: kDaemonShutdownSteps.cli,
    label: 'stopping the command-line host',
  );
  await runBounded(
    container.read(agentControllerProvider.notifier).shutdown,
    timeout: kDaemonShutdownSteps.agent,
    label: 'stopping the agent',
  );
  final remote = side.services.shutdownRemote;
  if (remote != null) {
    await runBounded(
      remote,
      timeout: kDaemonShutdownSteps.remote,
      label: 'closing the ssh masters',
    );
  }
}
